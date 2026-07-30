using Microsoft.Win32;
using System.Text.Json;

namespace MacMakeover.MenuBar;

internal static class Program
{
    private const string MutexName = "Local\\MacMakeover.MenuBar";

    [STAThread]
    private static void Main(string[] args)
    {
        var preview = args.Any(arg => arg.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        var previewAll = args.Any(arg => arg.Equals("--preview-all", StringComparison.OrdinalIgnoreCase));
        var previewPower = args.FirstOrDefault(arg => arg.StartsWith("--preview-power=", StringComparison.OrdinalIgnoreCase))?
            .Split('=', 2)[1];
        if (args.Length >= 2 && args[0].Equals("--snapshot-tray", StringComparison.OrdinalIgnoreCase))
        {
            File.WriteAllText(args[1], JsonSerializer.Serialize(
                TrayAppProvider.Capture(),
                new JsonSerializerOptions { WriteIndented = true }));
            return;
        }
        if (args.Any(arg => arg.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            Environment.ExitCode = PowerStateSelfTest() ? 0 : 2;
            return;
        }
        var mutexName = preview ? MutexName + ".Preview" : MutexName;
        using var mutex = new Mutex(initiallyOwned: true, mutexName, out var createdNew);
        if (!createdNew) return;

        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, e) => AppLog.Write("Thread exception: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => AppLog.Write("Unhandled exception: " + e.ExceptionObject);
        using var context = new MenuBarContext(preview, previewAll, preview ? previewPower : null);
        Application.Run(context);
    }

    private static bool PowerStateSelfTest()
    {
        var battery = SystemSnapshot.Empty with
        {
            BatteryPercent = 42,
            OnAcPower = false,
            Charging = false,
            PowerMode = PowerModeKind.Saver
        };
        var charging = battery with { OnAcPower = true, Charging = true, PowerMode = PowerModeKind.Performance };
        var pluggedIn = battery with { BatteryPercent = 94, OnAcPower = true, Charging = false, PowerMode = PowerModeKind.Balanced };
        return SystemStateProvider.ClassifyPowerMode(new Guid("961cc777-2547-4f9d-8174-7d86181b8a7a")) == PowerModeKind.Saver &&
               SystemStateProvider.ClassifyPowerMode(Guid.Empty) == PowerModeKind.Balanced &&
               SystemStateProvider.ClassifyPowerMode(new Guid("381b4222-f694-41f0-9685-ff5bb260df2e")) == PowerModeKind.Balanced &&
               SystemStateProvider.ClassifyPowerMode(new Guid("ded574b5-45a0-4f42-8737-46345c09c238")) == PowerModeKind.Performance &&
               MenuBarForm.PowerSourceLabel(battery) == "42%" &&
               MenuBarForm.PowerModeLabel(battery.PowerMode) == "Power saver" &&
               MenuBarForm.PowerSourceLabel(charging) == "42%" &&
               MenuBarForm.ShowsExternalPowerIndicator(charging) &&
               MenuBarForm.PowerModeLabel(charging.PowerMode) == "High performance" &&
               MenuBarForm.PowerSourceLabel(pluggedIn) == "94%" &&
               MenuBarForm.ShowsExternalPowerIndicator(pluggedIn) &&
               !MenuBarForm.ShowsExternalPowerIndicator(battery) &&
               MenuBarForm.PowerModeLabel(pluggedIn.PowerMode) == "Balanced" &&
               SystemStateProvider.FriendlyAppName("notepad", "handover.txt - Notepad", "Notepad") == "Notepad" &&
               SystemStateProvider.FriendlyAppName("mspaint", "Untitled - Paint", "mspaint.exe") == "Paint" &&
               SystemStateProvider.FriendlyAppName("acmeeditor", "Quarterly Plan.txt - Acme Editor", "Acme Editor") == "Acme Editor" &&
               SystemStateProvider.FriendlyAppName("acmeeditor", "Quarterly Plan.txt - Acme Editor") == "acmeeditor" &&
               SystemStateProvider.FriendlyAppName("ApplicationFrameHost", "Settings", "Application Frame Host") == "Settings" &&
               TrayAppProvider.ExpandExecutablePath("{F38BF404-1D43-42F2-9305-67DE0B28FC23}\\explorer.exe") == Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe") &&
               TelemetryLayoutSelfTest() &&
               AppBarRegistrationSelfTest() &&
               RenderedNotificationTokenSelfTest() &&
               MenuBarForm.IsShowDesktopCorner(new Point(0, 0), new Size(1280, 20), 8) &&
               MenuBarForm.IsShowDesktopCorner(new Point(1279, 0), new Size(1280, 20), 8) &&
               !MenuBarForm.IsShowDesktopCorner(new Point(8, 0), new Size(1280, 20), 8) &&
               !MenuBarForm.IsShowDesktopCorner(new Point(1271, 8), new Size(1280, 20), 8);
    }

    private static bool AppBarRegistrationSelfTest()
    {
        if (MenuBarForm.IsAppBarRegistrationAccepted(UIntPtr.Zero)) return false;
        if (!MenuBarForm.IsAppBarRegistrationAccepted((UIntPtr)1)) return false;
        if (!MenuBarForm.IsAppBarRegistrationAccepted(new UIntPtr(42))) return false;

        // Already registered: one reassert PositionAppBar.
        if (MenuBarForm.DecideStartupReassertFollowUp(wasRegistered: true, isRegistered: true) !=
            MenuBarForm.StartupReassertFollowUp.PositionAppBar)
        {
            return false;
        }

        // Retry ABM_NEW succeeded: RegisterAppBar already positioned once — no second call.
        if (MenuBarForm.DecideStartupReassertFollowUp(wasRegistered: false, isRegistered: true) !=
            MenuBarForm.StartupReassertFollowUp.None)
        {
            return false;
        }

        // ABM_NEW still failed: visible DPI bounds only, never ABM_SETPOS.
        if (MenuBarForm.DecideStartupReassertFollowUp(wasRegistered: false, isRegistered: false) !=
            MenuBarForm.StartupReassertFollowUp.ApplyVisibleBoundsOnly)
        {
            return false;
        }

        // Registered flag lost without a new reservation: fall back to visible bounds.
        if (MenuBarForm.DecideStartupReassertFollowUp(wasRegistered: true, isRegistered: false) !=
            MenuBarForm.StartupReassertFollowUp.ApplyVisibleBoundsOnly)
        {
            return false;
        }

        var bounds = MenuBarForm.ComputeTopBarBounds(new Rectangle(100, 200, 1920, 1080), 30);
        return bounds == new Rectangle(100, 200, 1920, 30) &&
               MenuBarForm.ComputeTopBarBounds(new Rectangle(0, 0, 1280, 800), 0) ==
               new Rectangle(0, 0, 1280, 1);
    }

    private static bool RenderedNotificationTokenSelfTest()
    {
        var trays = new[]
        {
            new TrayAppSnapshot("key-a", "Awake & Available", @"C:\Apps\Awake.exe", true),
            new TrayAppSnapshot("key-b", "Other", @"C:\Apps\Other.exe", false)
        };
        var baseline = SystemSnapshot.Empty with
        {
            CpuPercent = 12,
            UsedMemoryGb = 8.4,
            TotalMemoryGb = 16.0,
            DownloadBytesPerSecond = 1500,
            UploadBytesPerSecond = 500,
            BatteryPercent = 77,
            OnAcPower = false,
            Charging = false,
            PowerMode = PowerModeKind.Balanced,
            Connection = ConnectionKind.Wifi,
            ConnectionName = "Wi-Fi",
            ActiveApp = "Notepad",
            TrayApps = trays
        };
        var minuteA = new DateTime(2026, 7, 30, 14, 5, 10);
        var minuteALater = new DateTime(2026, 7, 30, 14, 5, 59);
        var minuteB = new DateTime(2026, 7, 30, 14, 6, 0);
        var tokenA = SystemStateProvider.BuildRenderedNotificationToken(baseline, minuteA);
        var tokenSameMinute = SystemStateProvider.BuildRenderedNotificationToken(baseline, minuteALater);
        var tokenNextMinute = SystemStateProvider.BuildRenderedNotificationToken(baseline, minuteB);

        // Identical rendered state within the same minute must suppress Changed.
        if (tokenA != tokenSameMinute) return false;
        if (SystemStateProvider.NotificationTokenChanged(tokenA, tokenSameMinute)) return false;

        // Clock advances at minute resolution so date/time still repaints.
        if (tokenA == tokenNextMinute) return false;
        if (!SystemStateProvider.NotificationTokenChanged(tokenA, tokenNextMinute)) return false;

        // Network buckets match FormatRate thresholds (B / K / M).
        if (SystemStateProvider.FormatNetworkRate(500) != "500B") return false;
        if (SystemStateProvider.FormatNetworkRate(1023) != "1023B") return false;
        if (SystemStateProvider.FormatNetworkRate(1024) != "1K") return false;
        if (SystemStateProvider.FormatNetworkRate(1535) != "1K") return false;
        if (SystemStateProvider.FormatNetworkRate(1536) != "2K") return false;
        if (SystemStateProvider.FormatNetworkRate(1024L * 1024L) != "1.0M") return false;
        if (SystemStateProvider.FormatNetworkRate(1024L * 1024L + 40L * 1024L) != "1.0M") return false;
        if (SystemStateProvider.FormatNetworkRate(1024L * 1024L + 60L * 1024L) != "1.1M") return false;

        var sameKBucket = baseline with { DownloadBytesPerSecond = 1024, UploadBytesPerSecond = 0 };
        var sameKBucketAlt = baseline with { DownloadBytesPerSecond = 1535, UploadBytesPerSecond = 0 };
        if (SystemStateProvider.BuildRenderedNotificationToken(sameKBucket, minuteA) !=
            SystemStateProvider.BuildRenderedNotificationToken(sameKBucketAlt, minuteA))
        {
            return false;
        }

        var nextKBucket = baseline with { DownloadBytesPerSecond = 1536, UploadBytesPerSecond = 0 };
        if (SystemStateProvider.BuildRenderedNotificationToken(sameKBucket, minuteA) ==
            SystemStateProvider.BuildRenderedNotificationToken(nextKBucket, minuteA))
        {
            return false;
        }

        // CPU integer, memory rounding, active app, tray list, battery/power/connection.
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { CpuPercent = 13 }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { UsedMemoryGb = 8.6 }, minuteA) == tokenA)
            return false;
        // 8.4 and 8.4... still round to the same painted "8".
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { UsedMemoryGb = 8.4 }, minuteA) != tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { ActiveApp = "Paint" }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { BatteryPercent = 76 }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { OnAcPower = true }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { Charging = true }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { PowerMode = PowerModeKind.Performance }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { Connection = ConnectionKind.Ethernet }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(baseline with { ConnectionName = "Ethernet" }, minuteA) == tokenA)
            return false;
        if (SystemStateProvider.BuildRenderedNotificationToken(
                baseline with { TrayApps = trays.Take(1).ToArray() }, minuteA) == tokenA)
        {
            return false;
        }

        // Memory paint uses :0; 8.49 still paints as 8 while 8.5 paints as 9.
        var memoryEight = baseline with { UsedMemoryGb = 8.49 };
        var memoryNine = baseline with { UsedMemoryGb = 8.5 };
        if (SystemStateProvider.BuildRenderedNotificationToken(memoryEight, minuteA) !=
            SystemStateProvider.BuildRenderedNotificationToken(baseline with { UsedMemoryGb = 8.0 }, minuteA))
        {
            return false;
        }
        if (SystemStateProvider.BuildRenderedNotificationToken(memoryEight, minuteA) ==
            SystemStateProvider.BuildRenderedNotificationToken(memoryNine, minuteA))
        {
            return false;
        }

        return true;
    }

    private static bool TelemetryLayoutSelfTest()
    {
        const int width = 1280;
        const int groupWidth = 460;
        const int leftEnd = 150;
        const int rightStart = 1010;
        var normal = MenuBarForm.CalculateTelemetryX(width, groupWidth, leftEnd, rightStart, 8);
        var scaled = MenuBarForm.CalculateTelemetryX(
            width * 3 / 2,
            groupWidth * 3 / 2,
            leftEnd * 3 / 2,
            rightStart * 3 / 2,
            12);
        var physicalCenter = (width - groupWidth) / 2;
        return normal < physicalCenter &&
               normal >= leftEnd + 8 &&
               normal + groupWidth <= rightStart - 8 &&
               Math.Abs(scaled - normal * 3 / 2) <= 1 &&
               MenuBarForm.CalculateTelemetryX(800, 620, 120, 700, 8) == 128;
    }
}

internal sealed class MenuBarContext : ApplicationContext
{
    private readonly bool _preview;
    private readonly bool _previewAll;
    private readonly string? _previewPower;
    private readonly SystemStateProvider _state = new();
    private readonly List<MenuBarForm> _bars = [];
    private bool _disposed;

    public MenuBarContext(bool preview, bool previewAll, string? previewPower)
    {
        _preview = preview;
        _previewAll = previewAll;
        _previewPower = previewPower;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        RebuildBars();
        _state.Start();
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        if (_disposed) return;
        var dispatcher = _bars.FirstOrDefault();
        if (dispatcher is { IsDisposed: false, IsHandleCreated: true } && dispatcher.InvokeRequired)
        {
            try { dispatcher.BeginInvoke(new Action(() => OnDisplaySettingsChanged(sender, e))); }
            catch (InvalidOperationException) { }
            return;
        }
        foreach (var bar in _bars.ToArray()) bar.Close();
        _bars.Clear();
        RebuildBars();
    }

    private void RebuildBars()
    {
        var screens = _preview && !_previewAll
            ? Screen.AllScreens.Where(screen => screen.Primary).Take(1)
            : Screen.AllScreens.AsEnumerable();

        foreach (var screen in screens)
        {
            var bar = new MenuBarForm(screen, _state, _preview, _previewPower);
            _bars.Add(bar);
            bar.Show();
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_disposed)
        {
            _disposed = true;
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            foreach (var bar in _bars.ToArray()) bar.Dispose();
            _bars.Clear();
            _state.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal static class AppLog
{
    public static void Write(string message)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "MacMakeover");
            Directory.CreateDirectory(directory);
            File.AppendAllText(
                Path.Combine(directory, "menu-bar.log"),
                $"{DateTime.Now:s} {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must not affect the desktop shell surface.
        }
    }
}
