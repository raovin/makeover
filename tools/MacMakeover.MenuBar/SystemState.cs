using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;

namespace MacMakeover.MenuBar;

internal enum ConnectionKind
{
    Offline,
    Wifi,
    Ethernet,
    Tethered,
    Vpn
}

internal enum PowerModeKind
{
    Saver,
    Balanced,
    Performance,
    Unknown
}

internal sealed record SystemSnapshot(
    int CpuPercent,
    double UsedMemoryGb,
    double TotalMemoryGb,
    long DownloadBytesPerSecond,
    long UploadBytesPerSecond,
    int BatteryPercent,
    bool OnAcPower,
    bool Charging,
    PowerModeKind PowerMode,
    ConnectionKind Connection,
    string ConnectionName,
    string ActiveApp)
{
    public static SystemSnapshot Empty { get; } = new(
        0, 0, 0, 0, 0, 100, true, false, PowerModeKind.Balanced,
        ConnectionKind.Offline, "Offline", "Finder");
}

internal sealed class SystemStateProvider : IDisposable
{
    private readonly object _gate = new();
    private readonly System.Threading.Timer _timer;
    private readonly Dictionary<string, (long Received, long Sent)> _networkSamples = new();
    private SystemSnapshot _snapshot = SystemSnapshot.Empty;
    private DateTime _networkSampledAt = DateTime.UtcNow;
    private ulong _previousIdle;
    private ulong _previousKernel;
    private ulong _previousUser;
    private string _lastActiveApp = "Finder";
    private int _polling;
    private bool _disposed;

    public SystemStateProvider()
    {
        _timer = new System.Threading.Timer(_ => Poll(), null, Timeout.Infinite, Timeout.Infinite);
    }

    public event EventHandler? Changed;

    public SystemSnapshot Snapshot
    {
        get
        {
            lock (_gate) return _snapshot;
        }
    }

    public void Start()
    {
        Poll();
        _timer.Change(1000, 1500);
    }

    private void Poll()
    {
        if (_disposed || Interlocked.Exchange(ref _polling, 1) != 0) return;
        try
        {
            var cpu = ReadCpuPercent();
            var (usedMemory, totalMemory) = ReadMemory();
            var (connection, interfaceName, received, sent) = ReadNetwork();
            var (down, up) = CalculateNetworkRates(interfaceName, received, sent);
            var power = SystemInformation.PowerStatus;
            var battery = power.BatteryLifePercent < 0
                ? 100
                : Math.Clamp((int)Math.Round(power.BatteryLifePercent * 100), 0, 100);
            var onAcPower = power.PowerLineStatus == PowerLineStatus.Online;
            var charging = power.BatteryChargeStatus.HasFlag(BatteryChargeStatus.Charging);
            var powerMode = ReadPowerMode(onAcPower);
            var activeApp = ReadActiveApp();

            lock (_gate)
            {
                _snapshot = new SystemSnapshot(
                    cpu,
                    usedMemory,
                    totalMemory,
                    down,
                    up,
                    battery,
                    onAcPower,
                    charging,
                    powerMode,
                    connection,
                    interfaceName,
                    activeApp);
            }
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            AppLog.Write("State poll failed: " + ex.Message);
        }
        finally
        {
            Volatile.Write(ref _polling, 0);
        }
    }

    private static PowerModeKind ReadPowerMode(bool onAcPower)
    {
        try
        {
            var result = onAcPower
                ? NativeMethods.PowerGetUserConfiguredACPowerMode(out var configured)
                : NativeMethods.PowerGetUserConfiguredDCPowerMode(out configured);
            if (result == 0) return ClassifyPowerMode(configured);
            if (NativeMethods.PowerGetEffectiveOverlayScheme(out var effective) == 0)
            {
                return ClassifyPowerMode(effective);
            }
        }
        catch (EntryPointNotFoundException) { }
        catch (DllNotFoundException) { }
        return PowerModeKind.Unknown;
    }

    internal static PowerModeKind ClassifyPowerMode(Guid mode)
    {
        if (mode == new Guid("961cc777-2547-4f9d-8174-7d86181b8a7a")) return PowerModeKind.Saver;
        if (mode == Guid.Empty || mode == new Guid("381b4222-f694-41f0-9685-ff5bb260df2e"))
        {
            return PowerModeKind.Balanced;
        }
        if (mode == new Guid("ded574b5-45a0-4f42-8737-46345c09c238")) return PowerModeKind.Performance;
        return PowerModeKind.Unknown;
    }

    private int ReadCpuPercent()
    {
        if (!NativeMethods.GetSystemTimes(out var idle, out var kernel, out var user)) return 0;
        var idleTicks = idle.ToUInt64();
        var kernelTicks = kernel.ToUInt64();
        var userTicks = user.ToUInt64();
        if (_previousKernel == 0)
        {
            _previousIdle = idleTicks;
            _previousKernel = kernelTicks;
            _previousUser = userTicks;
            return 0;
        }

        var idleDelta = idleTicks - _previousIdle;
        var totalDelta = kernelTicks - _previousKernel + userTicks - _previousUser;
        _previousIdle = idleTicks;
        _previousKernel = kernelTicks;
        _previousUser = userTicks;
        if (totalDelta == 0) return 0;
        return Math.Clamp((int)Math.Round(100d * (totalDelta - idleDelta) / totalDelta), 0, 100);
    }

    private static (double Used, double Total) ReadMemory()
    {
        var status = new NativeMethods.MemoryStatusEx();
        if (!NativeMethods.GlobalMemoryStatusEx(status)) return (0, 0);
        var total = status.TotalPhys / 1024d / 1024d / 1024d;
        var used = (status.TotalPhys - status.AvailPhys) / 1024d / 1024d / 1024d;
        return (used, total);
    }

    private static (ConnectionKind Kind, string Name, long Received, long Sent) ReadNetwork()
    {
        var active = NetworkInterface.GetAllNetworkInterfaces()
            .Where(network => network.OperationalStatus == OperationalStatus.Up)
            .Where(network => network.NetworkInterfaceType is not NetworkInterfaceType.Loopback and not NetworkInterfaceType.Unknown)
            .ToArray();

        if (active.Length == 0) return (ConnectionKind.Offline, "Offline", 0, 0);

        NetworkInterface? best = null;
        if (NativeMethods.GetBestInterface(BitConverter.ToUInt32(IPAddress.Parse("1.1.1.1").GetAddressBytes()), out var bestIndex) == 0)
        {
            best = active.FirstOrDefault(network =>
            {
                try { return network.GetIPProperties().GetIPv4Properties()?.Index == bestIndex; }
                catch { return false; }
            });
        }

        best ??= active.FirstOrDefault(network => network.NetworkInterfaceType == NetworkInterfaceType.Wireless80211);
        best ??= active.FirstOrDefault();
        if (best is null) return (ConnectionKind.Offline, "Offline", 0, 0);

        var name = string.IsNullOrWhiteSpace(best.Name) ? best.Description : best.Name;
        var searchable = (name + " " + best.Description).ToLowerInvariant();
        var kind = searchable.Contains("wireguard") || searchable.Contains("tailscale") ||
                   searchable.Contains("openvpn") || searchable.Contains("proton") ||
                   searchable.Contains("surfshark") || searchable.Contains("yggdrasil") ||
                   searchable.Contains(" vpn") || best.NetworkInterfaceType is NetworkInterfaceType.Ppp or NetworkInterfaceType.Tunnel
            ? ConnectionKind.Vpn
            : searchable.Contains("rndis") || searchable.Contains("tether") ||
              searchable.Contains("iphone") || searchable.Contains("android") || searchable.Contains("mobile")
                ? ConnectionKind.Tethered
                : best.NetworkInterfaceType == NetworkInterfaceType.Wireless80211
                    ? ConnectionKind.Wifi
                    : ConnectionKind.Ethernet;

        var stats = best.GetIPv4Statistics();
        return (kind, name, stats.BytesReceived, stats.BytesSent);
    }

    private (long Down, long Up) CalculateNetworkRates(string interfaceName, long received, long sent)
    {
        var now = DateTime.UtcNow;
        var elapsed = Math.Max((now - _networkSampledAt).TotalSeconds, 0.1);
        _networkSampledAt = now;
        if (!_networkSamples.TryGetValue(interfaceName, out var previous))
        {
            _networkSamples.Clear();
            _networkSamples[interfaceName] = (received, sent);
            return (0, 0);
        }

        _networkSamples[interfaceName] = (received, sent);
        return (
            Math.Max(0, (long)((received - previous.Received) / elapsed)),
            Math.Max(0, (long)((sent - previous.Sent) / elapsed)));
    }

    private string ReadActiveApp()
    {
        var window = NativeMethods.GetForegroundWindow();
        if (window == IntPtr.Zero || NativeMethods.IsIconic(window))
        {
            _lastActiveApp = "Finder";
            return _lastActiveApp;
        }
        NativeMethods.GetWindowThreadProcessId(window, out var processId);
        if (processId == 0) return _lastActiveApp;

        try
        {
            using var process = Process.GetProcessById((int)processId);
            var processName = process.ProcessName;
            if (processName.StartsWith("MacMakeover.", StringComparison.OrdinalIgnoreCase) ||
                processName.Equals("seelen-ui", StringComparison.OrdinalIgnoreCase) ||
                processName.Equals("ShellExperienceHost", StringComparison.OrdinalIgnoreCase) ||
                processName.Equals("StartMenuExperienceHost", StringComparison.OrdinalIgnoreCase) ||
                processName.Equals("SearchHost", StringComparison.OrdinalIgnoreCase))
            {
                return _lastActiveApp;
            }

            _lastActiveApp = FriendlyAppName(processName, process.MainWindowTitle);
        }
        catch
        {
            // A process can exit between the foreground query and name lookup.
        }
        return _lastActiveApp;
    }

    private static string FriendlyAppName(string processName, string title)
    {
        var mapped = processName.ToLowerInvariant() switch
        {
            "explorer" => "Finder",
            "applicationframehost" => FirstTitleSegment(title),
            "msedge" => "Microsoft Edge",
            "chrome" => "Google Chrome",
            "firefox" => "Firefox",
            "code" => "Visual Studio Code",
            "rider64" => "Rider",
            "devenv" => "Visual Studio",
            "windowsterminal" => "Terminal",
            "powershell" or "pwsh" => "PowerShell",
            "snippingtool" => "Snipping Tool",
            "teams" or "ms-teams" => "Microsoft Teams",
            "outlook" or "olk" => "Outlook",
            "claude" => "Claude",
            "codex" => "Codex",
            _ => FirstTitleSegment(title)
        };
        if (string.IsNullOrWhiteSpace(mapped)) mapped = processName;
        return mapped.Length > 32 ? mapped[..29] + "..." : mapped;
    }

    private static string FirstTitleSegment(string title)
    {
        if (string.IsNullOrWhiteSpace(title)) return string.Empty;
        var separators = new[] { " - ", "\u2014", " | " };
        foreach (var separator in separators)
        {
            var index = title.IndexOf(separator, StringComparison.Ordinal);
            if (index > 0) return title[..index].Trim();
        }
        return title.Trim();
    }

    public void Dispose()
    {
        _disposed = true;
        _timer.Dispose();
    }
}
