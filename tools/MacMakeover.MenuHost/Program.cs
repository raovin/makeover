using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;

namespace MacMakeover.MenuHost;

internal static class Program
{
    private const string PipeName = "MacMakeover.MenuHost";
    private const string MutexName = "Local\\MacMakeover.MenuHost";

    [STAThread]
    private static void Main(string[] args)
    {
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        var command = args.Length >= 2 && args[0].Equals("--show", StringComparison.OrdinalIgnoreCase)
            ? args[1]
            : string.Empty;

        if (!createdNew)
        {
            if (!string.IsNullOrWhiteSpace(command))
            {
                SendCommand(command, 350);
            }
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, e) => Log("Thread exception: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("Unhandled exception: " + e.ExceptionObject);
        using var context = new MenuContext();
        _ = Task.Run(() => RunPipeServerAsync(context));

        if (!string.IsNullOrWhiteSpace(command))
        {
            context.Post(command);
        }

        Application.Run(context);
    }

    internal static void Log(string message)
    {
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "MacMakeover");
            Directory.CreateDirectory(dir);
            File.AppendAllText(
                Path.Combine(dir, "menu-host.log"),
                $"{DateTime.Now:s} {message}{Environment.NewLine}",
                Encoding.UTF8);
        }
        catch
        {
            // Logging must never be able to take down the menu host.
        }
    }

    private static async Task RunPipeServerAsync(MenuContext context)
    {
        while (!context.IsDisposed)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    PipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
                await server.WaitForConnectionAsync(context.Token).ConfigureAwait(false);
                using var reader = new StreamReader(server, Encoding.UTF8, leaveOpen: true);
                var command = await reader.ReadLineAsync(context.Token).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(command))
                {
                    context.Post(command);
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch
            {
                await Task.Delay(150).ConfigureAwait(false);
            }
        }
    }

    internal static bool SendCommand(string command, int timeoutMs)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(timeoutMs);
            using var writer = new StreamWriter(client, Encoding.UTF8) { AutoFlush = true };
            writer.WriteLine(command);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

internal sealed class MenuContext : ApplicationContext
{
    private readonly CancellationTokenSource _cts = new();
    private readonly Control _invoker = new();
    private Form? _current;

    public MenuContext()
    {
        _invoker.CreateControl();
    }

    public CancellationToken Token => _cts.Token;

    public bool IsDisposed { get; private set; }

    public void Post(string command)
    {
        if (_invoker.IsDisposed) return;
        Program.Log("Post " + command);
        _invoker.BeginInvoke(new Action(() => ShowCommand(command)));
    }

    private void ShowCommand(string command)
    {
        try
        {
            Program.Log("ShowCommand " + command);
            var previous = _current;
            _current = null;
            previous?.Close();
            if (previous is { IsDisposed: false })
            {
                previous.Dispose();
            }

            _current = command.Trim().ToLowerInvariant() switch
            {
                "apple" => MenuForm.CreateApple(),
                "control" => MenuForm.CreateControlCenter(),
                "network" => MenuForm.CreateNetwork(),
                "bluetooth" => MenuForm.CreateBluetooth(),
                _ => null
            };

            if (_current is null) return;
            Program.Log($"Created {_current.Text} at {_current.Left},{_current.Top} size {_current.Width}x{_current.Height}");
            var shown = _current;
            shown.FormClosed += (_, _) =>
            {
                if (ReferenceEquals(_current, shown))
                {
                    _current = null;
                }
            };
            shown.Show();
            BringShownMenuForward(shown);
            shown.Invalidate(invalidateChildren: true);
            shown.Update();
            shown.Refresh();
            Program.Log($"Shown {shown.Text}, visible={shown.Visible}, handle={shown.Handle}");
        }
        catch (Exception ex)
        {
            Program.Log("ShowCommand failed: " + ex);
        }
    }

    private static void BringShownMenuForward(Form form)
    {
        NativeMethods.ShowWithoutActivation(form);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            IsDisposed = true;
            _cts.Cancel();
            _current?.Dispose();
            _invoker.Dispose();
            _cts.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal sealed class MenuForm : Form
{
    private readonly Color _panel = Color.FromArgb(30, 35, 46);
    private readonly Color _panelTop = Color.FromArgb(40, 47, 61);
    private readonly Color _panelBottom = Color.FromArgb(23, 27, 36);
    private readonly Color _panelBorder = Color.FromArgb(76, 88, 108);
    private readonly Color _card = Color.FromArgb(48, 54, 70);
    private readonly Color _cardBottom = Color.FromArgb(40, 45, 59);
    private readonly Color _cardHover = Color.FromArgb(62, 70, 89);
    private readonly Color _hover = Color.FromArgb(59, 116, 239);
    private readonly Color _separator = Color.FromArgb(78, 87, 103);
    private readonly Color _primaryText = Color.FromArgb(248, 250, 253);
    private readonly Color _secondaryText = Color.FromArgb(184, 192, 205);
    private readonly List<MenuRow> _rows = [];
    private readonly System.Windows.Forms.Timer _outsideClickTimer;
    private readonly System.Windows.Forms.Timer _systemSwitchTimer;
    private readonly Font _regularFont;
    private readonly Font _boldFont;
    private readonly Font _smallFont;
    private readonly Font _smallBoldFont;
    private readonly Font _iconFont;
    private readonly CancellationTokenSource _lifetimeCts = new();
    private readonly Screen _targetScreen;
    private readonly int _logicalWidth;
    private bool _anchorRight;
    private int _logicalTop = 38;
    private int _logicalMargin = 8;
    private DateTime _shownAt;
    private IntPtr _foregroundAtShown;
    private bool _wasLeftMouseDown;
    private bool _hasShown;
    private bool _managedResourcesDisposed;
    private int _hoverIndex = -1;
    private int _dragRow = -1;

    private MenuForm(int width)
    {
        // We scale every owner-drawn constant ourselves via LogicalToDeviceUnits, so the
        // framework must NOT also auto-scale (that would double-apply DPI).
        AutoScaleMode = AutoScaleMode.None;
        BackColor = _panel;
        // Fonts are in points, so GDI already renders them at the correct physical size per DPI.
        _regularFont = new Font("Segoe UI", 9.7F, FontStyle.Regular, GraphicsUnit.Point);
        _boldFont = new Font("Segoe UI", 9.8F, FontStyle.Bold, GraphicsUnit.Point);
        _smallFont = new Font("Segoe UI", 8.3F, FontStyle.Regular, GraphicsUnit.Point);
        _smallBoldFont = new Font("Segoe UI", 8.6F, FontStyle.Bold, GraphicsUnit.Point);
        _iconFont = new Font("Segoe Fluent Icons", 11F, FontStyle.Regular, GraphicsUnit.Point);
        Font = _regularFont;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        // Capture the initiating pointer's monitor before the handle exists. Setting an
        // initial location on that monitor also lets WinForms create the handle at the
        // correct per-monitor DPI instead of creating on primary and moving afterward.
        _targetScreen = Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        Location = _targetScreen.Bounds.Location;
        // Menus must never sit above system surfaces such as Alt+Tab or the Snipping
        // Tool capture overlay. HWND_TOP is enough to place this popup above the
        // current app while keeping it in the normal (non-topmost) z-order band.
        TopMost = false;
        _logicalWidth = width;
        KeyPreview = true;
        DoubleBuffered = true;

        _outsideClickTimer = new System.Windows.Forms.Timer { Interval = 25 };
        _outsideClickTimer.Tick += (_, _) => CloseAfterOutsideClick();
        _systemSwitchTimer = new System.Windows.Forms.Timer { Interval = 25 };
        _systemSwitchTimer.Tick += (_, _) => CloseIfSystemSwitcherStarts();
        Shown += (_, _) =>
        {
            _shownAt = DateTime.UtcNow;
            _foregroundAtShown = NativeMethods.GetForegroundWindowHandle();
            _hasShown = true;
            _outsideClickTimer.Start();
            _systemSwitchTimer.Start();
        };
        FormClosed += (_, _) =>
        {
            _outsideClickTimer.Dispose();
            _systemSwitchTimer.Dispose();
        };
        KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
        };
        // Do not close on Deactivate. Seelen, shell URI launches, screenshot tools, and
        // the desktop compositor can briefly take focus away from a just-opened menu,
        // which made the Control Center vanish before it ever painted. The timer below
        // still handles normal click-away dismissal.
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            const int wsExToolWindow = 0x00000080;
            const int wsExNoActivate = 0x08000000;
            var cp = base.CreateParams;
            cp.ExStyle |= wsExToolWindow | wsExNoActivate;
            return cp;
        }
    }

    // All size/position math depends on DeviceDpi, which is only correct once the handle exists.
    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        NativeMethods.ApplyRoundedDarkChrome(Handle);
        Padding = new Padding(LogicalToDeviceUnits(10));
        Width = LogicalToDeviceUnits(_logicalWidth);
        FitHeight();

        // Screen bounds and window Location share the same physical coordinate space in
        // this DPI-aware process. Anchor to the screen that contained the initiating
        // pointer, not always to primary. Do NOT rescale Right by 96/DeviceDpi.
        var screen = _targetScreen.Bounds;
        var x = _anchorRight
            ? screen.Right - Width - LogicalToDeviceUnits(_logicalMargin)
            : screen.Left + LogicalToDeviceUnits(_logicalMargin);
        var top = screen.Top + LogicalToDeviceUnits(_logicalTop);
        Location = new Point(x, top);
        Program.Log($"Positioned {Text} at {Location.X},{Location.Y} on {_targetScreen.DeviceName} {screen.Width}x{screen.Height} dpi={DeviceDpi}");
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        using var brush = new LinearGradientBrush(ClientRectangle, _panelTop, _panelBottom, LinearGradientMode.Vertical);
        e.Graphics.FillRectangle(brush, ClientRectangle);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var brush = new LinearGradientBrush(ClientRectangle, _panelTop, _panelBottom, LinearGradientMode.Vertical))
        {
            e.Graphics.FillRectangle(brush, ClientRectangle);
        }

        var y = Padding.Top;
        for (var i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            var height = LogicalToDeviceUnits(row.Height);
            var rect = new Rectangle(Padding.Left, y, ClientSize.Width - Padding.Horizontal, height);

            switch (row.Kind)
            {
                case MenuRowKind.Header:
                    DrawHeader(e.Graphics, rect, row);
                    break;
                case MenuRowKind.Card:
                    DrawCard(e.Graphics, rect, row, i == _hoverIndex);
                    break;
                case MenuRowKind.IconCard:
                    DrawIconCard(e.Graphics, rect, row, i == _hoverIndex);
                    break;
                case MenuRowKind.Slider:
                    DrawSlider(e.Graphics, rect, row);
                    break;
                case MenuRowKind.Separator:
                    using (var pen = new Pen(_separator))
                    {
                        var lineY = rect.Top + (rect.Height / 2);
                        e.Graphics.DrawLine(pen, rect.Left + LogicalToDeviceUnits(8), lineY, rect.Right - LogicalToDeviceUnits(8), lineY);
                    }
                    break;
                default:
                    DrawItem(e.Graphics, rect, row, i == _hoverIndex);
                    break;
            }

            y += height;
        }

        var borderRect = Rectangle.Inflate(ClientRectangle, -1, -1);
        using var borderPath = RoundedRect(borderRect, LogicalToDeviceUnits(12));
        using var borderPen = new Pen(_panelBorder);
        e.Graphics.DrawPath(borderPen, borderPath);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_dragRow >= 0)
        {
            UpdateSliderFromX(_dragRow, e.X, commit: false);
            return;
        }

        var hit = HitTest(e.Location);
        if (hit == _hoverIndex) return;

        _hoverIndex = hit;
        Cursor = hit >= 0 && (_rows[hit].Action is not null || _rows[hit].Kind == MenuRowKind.Slider) ? Cursors.Hand : Cursors.Default;
        Invalidate();
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_hoverIndex == -1) return;

        _hoverIndex = -1;
        Cursor = Cursors.Default;
        Invalidate();
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button != MouseButtons.Left) return;

        var hit = HitTest(e.Location);
        var action = hit >= 0 ? _rows[hit].Action : null;
        if (action is null) return;

        Close();
        action();
    }

    public static MenuForm CreateApple(bool anchorRight = false)
    {
        var form = new MenuForm(248);
        form.Text = "Apple Menu";
        form._anchorRight = anchorRight;
        form.AddItem("About This Mac", () => Start("msinfo32.exe"));
        form.AddSeparator();
        form.AddItem("System Settings...", () => Start("ms-settings:"));
        form.AddItem("App Store", () => Start("ms-windows-store://home"));
        form.AddSeparator();
        form.AddItem("Recent Items", null, ">");
        form.AddSeparator();
        form.AddItem("Force Quit...", () => Start("taskmgr.exe"), "Ctrl+Shift+Esc");
        form.AddSeparator();
        form.AddItem("Sleep...", () => Confirm("Sleep", "Put this PC to sleep now?", "rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"));
        form.AddItem("Restart...", () => Confirm("Restart", "Restart this PC now?", "shutdown.exe", "/r /t 0"));
        form.AddItem("Shut Down...", () => Confirm("Shut Down", "Shut down this PC now?", "shutdown.exe", "/s /t 0"));
        form.AddSeparator();
        form.AddItem("Lock Screen", () => Start("rundll32.exe", "user32.dll,LockWorkStation"));
        form.AddItem($"Log Out {FriendlyUserName()}...", () => Confirm("Log Out", "Sign out now?", "shutdown.exe", "/l"));
        return form;
    }

    public static MenuForm CreateControlCenter()
    {
        var form = new MenuForm(292);
        form.Text = "Control Center";
        form._anchorRight = true;
        form.AddHeader("Control Center", GetBatterySummary());

        // Live tiles + working sliders are the point of this panel - keep them.
        // (The Display slider drives real WMI brightness; Sound drives Core Audio.)
        var wifi = form.AddIconCard("", "Wi-Fi", "Checking...", active: false, () => Program.SendCommand("network", 350));
        var bluetooth = form.AddIconCard("", "Bluetooth", "Checking...", active: false, () => Program.SendCommand("bluetooth", 350));

        var brightnessSlider = new SliderInfo
        {
            Glyph = "",
            Value = 0.5f,
            OnCommit = value => SetBrightnessAsync((int)Math.Round(value * 100))
        };
        form.AddSlider("Display", brightnessSlider);

        var volumeSlider = new SliderInfo
        {
            Glyph = "",
            Value = VolumeService.GetMasterVolume() ?? 0.5f,
            OnChange = VolumeService.SetMasterVolume
        };
        form.AddSlider("Sound", volumeSlider);

        form.AddSeparator();
        form.AddItem("System Settings...", () => Start("ms-settings:"));
        form.AddItem("Show Desktop", ToggleDesktop);
        form.AddSeparator();
        form.AddItem("Lock Screen", () => Start("rundll32.exe", "user32.dll,LockWorkStation"));
        form.AddItem("Sleep...", () => Confirm("Sleep", "Put this PC to sleep now?", "rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"));
        form.AddItem("Restart...", () => Confirm("Restart", "Restart this PC now?", "shutdown.exe", "/r /t 0"));
        form.AddItem("Shut Down...", () => Confirm("Shut Down", "Shut down this PC now?", "shutdown.exe", "/s /t 0"));

        form.LoadControlCenterStateAsync(wifi, bluetooth, brightnessSlider);
        return form;
    }

    public static MenuForm CreateNetwork()
    {
        var form = new MenuForm(292);
        form.Text = "Network";
        form._anchorRight = true;

        var currentSsid = ReadWifiSsid();
        form.AddHeader("Wi-Fi", currentSsid is null ? "Not connected" : $"Connected to {currentSsid}");
        form.AddItem("Wi-Fi Settings...", () => Start("ms-settings:network-wifi"));
        form.AddItem("Network Settings...", () => Start("ms-settings:network"));
        form.AddSeparator();

        var networks = ReadWifiNetworks()
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(7)
            .ToList();

        if (networks.Count == 0)
        {
            form.AddItem("No nearby networks found", null);
        }
        else
        {
            foreach (var network in networks)
            {
                var label = network;
                var detail = network.Equals(currentSsid, StringComparison.OrdinalIgnoreCase) ? "Connected" : string.Empty;
                form.AddItem(label, () => ConnectWifiProfileAsync(label), detail);
            }
        }

        form.AddSeparator();
        form.AddItem("Refresh", () => Program.SendCommand("network", 350));
        return form;
    }

    public static MenuForm CreateBluetooth()
    {
        var form = new MenuForm(292);
        form.Text = "Bluetooth";
        form._anchorRight = true;

        form.AddHeader("Bluetooth", ReadBluetoothOn() ? "On" : "Off");
        form.AddItem("Bluetooth Settings...", () => Start("ms-settings:bluetooth"));
        form.AddItem("Paired Devices...", () => Start("ms-settings:connecteddevices"));
        form.AddItem("Add Device...", () => Start("ms-settings:bluetooth"));
        form.AddSeparator();
        form.AddItem("Refresh", () => Program.SendCommand("bluetooth", 350));
        return form;
    }

    // Fill Wi-Fi SSID, Bluetooth state, and current brightness in the background so the
    // panel opens instantly and enriches itself a beat later.
    private void LoadControlCenterStateAsync(MenuRow wifi, MenuRow bluetooth, SliderInfo brightness)
    {
        var cancellationToken = _lifetimeCts.Token;
        _ = Task.Run(() =>
        {
            var ssid = ReadWifiSsid(cancellationToken);
            var bluetoothOn = ReadBluetoothOn(cancellationToken);
            var brightnessPercent = ReadBrightnessPercent(cancellationToken);

            try
            {
                if (cancellationToken.IsCancellationRequested || IsDisposed || Disposing) return;
                BeginInvoke(() =>
                {
                    if (cancellationToken.IsCancellationRequested || IsDisposed || Disposing) return;
                    wifi.Detail = ssid ?? "Not connected";
                    wifi.Active = ssid is not null;
                    bluetooth.Detail = bluetoothOn ? "On" : "Off";
                    bluetooth.Active = bluetoothOn;
                    if (brightnessPercent is { } pct)
                    {
                        brightness.Value = Math.Clamp(pct / 100f, 0f, 1f);
                    }

                    Invalidate();
                });
            }
            catch
            {
                // Panel may already be closed; state enrichment is best-effort.
            }
        }, cancellationToken);
    }

    private static string? ReadWifiSsid(CancellationToken cancellationToken = default)
    {
        try
        {
            var output = RunHidden("netsh", "wlan show interfaces", 2500, cancellationToken);
            string? ssid = null;
            var connected = false;
            foreach (var rawLine in output.Split('\n'))
            {
                var line = rawLine.Trim();
                if (line.StartsWith("State", StringComparison.OrdinalIgnoreCase) && line.Contains("connected", StringComparison.OrdinalIgnoreCase) && !line.Contains("disconnected", StringComparison.OrdinalIgnoreCase))
                {
                    connected = true;
                }

                if (ssid is null && line.StartsWith("SSID", StringComparison.OrdinalIgnoreCase) && !line.StartsWith("BSSID", StringComparison.OrdinalIgnoreCase))
                {
                    var idx = line.IndexOf(':');
                    if (idx > 0) ssid = line[(idx + 1)..].Trim();
                }
            }

            return connected && !string.IsNullOrWhiteSpace(ssid) ? ssid : null;
        }
        catch
        {
            return null;
        }
    }

    private static IEnumerable<string> ReadWifiNetworks()
    {
        var networks = new List<string>();
        try
        {
            var output = RunHidden("netsh", "wlan show networks mode=bssid", 4000);
            foreach (var rawLine in output.Split('\n'))
            {
                var line = rawLine.Trim();
                if (!line.StartsWith("SSID ", StringComparison.OrdinalIgnoreCase) ||
                    line.StartsWith("BSSID", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var idx = line.IndexOf(':');
                if (idx <= 0) continue;

                var ssid = line[(idx + 1)..].Trim();
                if (!string.IsNullOrWhiteSpace(ssid))
                {
                    networks.Add(ssid);
                }
            }
        }
        catch (Exception ex)
        {
            Program.Log("ReadWifiNetworks failed: " + ex.Message);
        }

        return networks;
    }

    private static void ConnectWifiProfileAsync(string ssid)
    {
        _ = Task.Run(() =>
        {
            try
            {
                var safeName = ssid.Replace("\"", string.Empty);
                RunHidden("netsh", $"wlan connect name=\"{safeName}\"", 7000);
            }
            catch (Exception ex)
            {
                Program.Log("Wi-Fi connect failed: " + ex.Message);
            }
        });
    }

    private static bool ReadBluetoothOn(CancellationToken cancellationToken = default)
    {
        try
        {
            var output = RunHidden("powershell.exe", "-NoProfile -NonInteractive -Command \"(Get-Service bthserv).Status\"", 4000, cancellationToken);
            return output.Contains("Running", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static IEnumerable<string> ReadBluetoothDevices()
    {
        var devices = new List<string>();
        try
        {
            const string command = "Get-PnpDevice -Class Bluetooth -Status OK | Where-Object { $_.FriendlyName -and $_.FriendlyName -notmatch 'Enumerator|Adapter|Protocol|Transport|RFCOMM|Generic Attribute|Microsoft Bluetooth|Intel' } | Select-Object -First 7 -ExpandProperty FriendlyName";
            var output = RunHidden("powershell.exe", "-NoProfile -NonInteractive -Command \"" + command + "\"", 2500);
            foreach (var rawLine in output.Split('\n'))
            {
                var name = rawLine.Trim();
                if (!string.IsNullOrWhiteSpace(name))
                {
                    devices.Add(name);
                }
            }
        }
        catch (Exception ex)
        {
            Program.Log("ReadBluetoothDevices failed: " + ex.Message);
        }

        return devices;
    }

    private static int? ReadBrightnessPercent(CancellationToken cancellationToken = default)
    {
        try
        {
            var output = RunHidden("powershell.exe", "-NoProfile -NonInteractive -Command \"(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightness).CurrentBrightness\"", 4000, cancellationToken);
            return int.TryParse(output.Trim(), out var value) ? value : null;
        }
        catch
        {
            return null;
        }
    }

    private static void SetBrightnessAsync(int percent)
    {
        _ = Task.Run(() =>
        {
            try
            {
                RunHidden(
                    "powershell.exe",
                    $"-NoProfile -NonInteractive -Command \"(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1,{Math.Clamp(percent, 0, 100)})\"",
                    5000);
            }
            catch (Exception ex)
            {
                Program.Log("SetBrightness failed: " + ex.Message);
            }
        });
    }

    private static string RunHidden(
        string fileName,
        string arguments,
        int timeoutMs,
        CancellationToken cancellationToken = default)
    {
        var psi = new ProcessStartInfo(fileName, arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var process = Process.Start(psi);
        if (process is null) return string.Empty;
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(timeoutMs);

        try
        {
            process.WaitForExitAsync(timeout.Token).GetAwaiter().GetResult();
            var output = outputTask.GetAwaiter().GetResult();
            _ = errorTask.GetAwaiter().GetResult();
            return output;
        }
        catch (OperationCanceledException)
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit(1000);
                }
            }
            catch
            {
                // The best-effort probe may already have exited.
            }

            return string.Empty;
        }
    }

    private static string FriendlyUserName()
    {
        var name = Environment.UserName;
        return name.Equals("VineethRao", StringComparison.OrdinalIgnoreCase) ? "Vineeth Rao" : name;
    }

    private void AddHeader(string title, string detail)
    {
        _rows.Add(new MenuRow(MenuRowKind.Header, title, detail, string.Empty, null, 54));
    }

    private void AddCard(string label, string detail, Action action)
    {
        _rows.Add(new MenuRow(MenuRowKind.Card, label, detail, string.Empty, action, 52));
    }

    private void AddItem(string label, Action? action, string shortcut = "")
    {
        _rows.Add(new MenuRow(MenuRowKind.Item, label, string.Empty, shortcut, action, 30));
    }

    private MenuRow AddIconCard(string glyph, string label, string detail, bool active, Action action)
    {
        var row = new MenuRow(MenuRowKind.IconCard, label, detail, string.Empty, action, 50)
        {
            Glyph = glyph,
            Active = active
        };
        _rows.Add(row);
        return row;
    }

    private MenuRow AddSlider(string label, SliderInfo slider)
    {
        var row = new MenuRow(MenuRowKind.Slider, label, string.Empty, string.Empty, null, 56)
        {
            Slider = slider
        };
        _rows.Add(row);
        return row;
    }

    private void AddSeparator()
    {
        _rows.Add(new MenuRow(MenuRowKind.Separator, string.Empty, string.Empty, string.Empty, null, 11));
    }

    private void FitHeight()
    {
        ClientSize = new Size(Width, _rows.Sum(row => LogicalToDeviceUnits(row.Height)) + Padding.Vertical);
    }

    private int HitTest(Point point)
    {
        var y = Padding.Top;
        for (var i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            var height = LogicalToDeviceUnits(row.Height);
            var rect = new Rectangle(Padding.Left, y, ClientSize.Width - Padding.Horizontal, height);
            if (rect.Contains(point)) return i;
            y += height;
        }

        return -1;
    }

    private void DrawHeader(Graphics graphics, Rectangle rect, MenuRow row)
    {
        var titleRect = new Rectangle(rect.Left + LogicalToDeviceUnits(10), rect.Top + LogicalToDeviceUnits(5), rect.Width - LogicalToDeviceUnits(20), LogicalToDeviceUnits(24));
        var detailRect = new Rectangle(rect.Left + LogicalToDeviceUnits(10), rect.Top + LogicalToDeviceUnits(28), rect.Width - LogicalToDeviceUnits(20), LogicalToDeviceUnits(20));
        TextRenderer.DrawText(graphics, row.Label, _boldFont, titleRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(graphics, row.Detail, _smallFont, detailRect, _secondaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void DrawCard(Graphics graphics, Rectangle rect, MenuRow row, bool hovered)
    {
        var cardRect = Rectangle.Inflate(rect, -LogicalToDeviceUnits(2), -LogicalToDeviceUnits(3));
        using (var brush = new LinearGradientBrush(cardRect, hovered ? _cardHover : _card, _cardBottom, LinearGradientMode.Vertical))
        using (var path = RoundedRect(cardRect, LogicalToDeviceUnits(8)))
        {
            graphics.FillPath(brush, path);
            using var pen = new Pen(Color.FromArgb(hovered ? 86 : 52, 255, 255, 255));
            graphics.DrawPath(pen, path);
        }

        var titleRect = new Rectangle(cardRect.Left + LogicalToDeviceUnits(12), cardRect.Top + LogicalToDeviceUnits(6), cardRect.Width - LogicalToDeviceUnits(24), LogicalToDeviceUnits(20));
        var detailRect = new Rectangle(cardRect.Left + LogicalToDeviceUnits(12), cardRect.Top + LogicalToDeviceUnits(26), cardRect.Width - LogicalToDeviceUnits(24), LogicalToDeviceUnits(18));
        TextRenderer.DrawText(graphics, row.Label, _smallBoldFont, titleRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(graphics, row.Detail, _smallFont, detailRect, _secondaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void DrawIconCard(Graphics graphics, Rectangle rect, MenuRow row, bool hovered)
    {
        var cardRect = Rectangle.Inflate(rect, -LogicalToDeviceUnits(2), -LogicalToDeviceUnits(3));
        using (var brush = new LinearGradientBrush(cardRect, hovered ? _cardHover : _card, _cardBottom, LinearGradientMode.Vertical))
        using (var path = RoundedRect(cardRect, LogicalToDeviceUnits(12)))
        {
            graphics.FillPath(brush, path);
            using var pen = new Pen(Color.FromArgb(hovered ? 90 : 54, 255, 255, 255));
            graphics.DrawPath(pen, path);
        }

        // Circular icon chip: accent blue when the feature is active, muted gray otherwise.
        var chipSize = LogicalToDeviceUnits(30);
        var chipRect = new Rectangle(
            cardRect.Left + LogicalToDeviceUnits(10),
            cardRect.Top + (cardRect.Height - chipSize) / 2,
            chipSize,
            chipSize);
        using (var chipBrush = new LinearGradientBrush(chipRect, row.Active ? Color.FromArgb(73, 140, 255) : Color.FromArgb(96, 104, 124), row.Active ? Color.FromArgb(35, 92, 215) : Color.FromArgb(70, 77, 94), LinearGradientMode.Vertical))
        {
            graphics.FillEllipse(chipBrush, chipRect);
        }
        using (var chipPen = new Pen(Color.FromArgb(70, 255, 255, 255)))
        {
            graphics.DrawEllipse(chipPen, chipRect);
        }

        TextRenderer.DrawText(graphics, row.Glyph, _iconFont, chipRect, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding);

        var textLeft = chipRect.Right + LogicalToDeviceUnits(10);
        var titleRect = new Rectangle(textLeft, cardRect.Top + LogicalToDeviceUnits(5), cardRect.Right - textLeft - LogicalToDeviceUnits(10), LogicalToDeviceUnits(18));
        var detailRect = new Rectangle(textLeft, cardRect.Top + LogicalToDeviceUnits(23), cardRect.Right - textLeft - LogicalToDeviceUnits(10), LogicalToDeviceUnits(16));
        TextRenderer.DrawText(graphics, row.Label, _smallBoldFont, titleRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(graphics, row.Detail, _smallFont, detailRect, _secondaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    // macOS-style thick pill slider: label above, full-width track with the icon riding
    // the filled end and a round knob at the value position.
    private void DrawSlider(Graphics graphics, Rectangle rect, MenuRow row)
    {
        if (row.Slider is not { } slider) return;

        var labelRect = new Rectangle(rect.Left + LogicalToDeviceUnits(12), rect.Top + LogicalToDeviceUnits(2), rect.Width - LogicalToDeviceUnits(24), LogicalToDeviceUnits(18));
        TextRenderer.DrawText(graphics, row.Label, _smallBoldFont, labelRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);

        var track = SliderTrackRect(rect);
        using (var backBrush = new LinearGradientBrush(track, Color.FromArgb(82, 255, 255, 255), Color.FromArgb(48, 255, 255, 255), LinearGradientMode.Vertical))
        using (var backPath = RoundedRect(track, track.Height / 2))
        {
            graphics.FillPath(backBrush, backPath);
            using var trackPen = new Pen(Color.FromArgb(36, 255, 255, 255));
            graphics.DrawPath(trackPen, backPath);
        }

        var knobRadius = track.Height / 2;
        var usable = track.Width - track.Height;
        var knobCx = track.Left + knobRadius + (int)(Math.Clamp(slider.Value, 0f, 1f) * usable);
        var filled = new Rectangle(track.Left, track.Top, knobCx + knobRadius - track.Left, track.Height);
        using (var fillBrush = new LinearGradientBrush(filled, Color.FromArgb(252, 254, 255), Color.FromArgb(214, 226, 245), LinearGradientMode.Vertical))
        using (var fillPath = RoundedRect(filled, track.Height / 2))
        {
            graphics.FillPath(fillBrush, fillPath);
        }

        var glyphRect = new Rectangle(track.Left, track.Top, track.Height, track.Height);
        TextRenderer.DrawText(graphics, slider.Glyph, _iconFont, glyphRect, Color.FromArgb(74, 78, 92), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding);

        var knobRect = new Rectangle(knobCx - knobRadius, track.Top, track.Height, track.Height);
        using var knobBrush = new SolidBrush(Color.White);
        graphics.FillEllipse(knobBrush, knobRect);
        using var knobPen = new Pen(Color.FromArgb(75, 0, 0, 0));
        graphics.DrawEllipse(knobPen, knobRect);
    }

    private Rectangle SliderTrackRect(Rectangle rowRect)
    {
        var height = LogicalToDeviceUnits(22);
        return new Rectangle(
            rowRect.Left + LogicalToDeviceUnits(12),
            rowRect.Bottom - height - LogicalToDeviceUnits(6),
            rowRect.Width - LogicalToDeviceUnits(24),
            height);
    }

    private Rectangle RowRect(int index)
    {
        var y = Padding.Top;
        for (var i = 0; i < index; i++)
        {
            y += LogicalToDeviceUnits(_rows[i].Height);
        }

        return new Rectangle(Padding.Left, y, ClientSize.Width - Padding.Horizontal, LogicalToDeviceUnits(_rows[index].Height));
    }

    private void UpdateSliderFromX(int rowIndex, int x, bool commit)
    {
        if (_rows[rowIndex].Slider is not { } slider) return;

        var track = SliderTrackRect(RowRect(rowIndex));
        var usable = Math.Max(1, track.Width - track.Height);
        var value = Math.Clamp((x - track.Left - (track.Height / 2f)) / usable, 0f, 1f);
        slider.Value = value;
        Invalidate();
        slider.OnChange?.Invoke(value);
        if (commit)
        {
            slider.OnCommit?.Invoke(value);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;

        var hit = HitTest(e.Location);
        if (hit >= 0 && _rows[hit].Kind == MenuRowKind.Slider)
        {
            _dragRow = hit;
            Capture = true;
            UpdateSliderFromX(hit, e.X, commit: false);
        }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (_dragRow < 0) return;

        UpdateSliderFromX(_dragRow, e.X, commit: true);
        _dragRow = -1;
        Capture = false;
    }

    private void DrawItem(Graphics graphics, Rectangle rect, MenuRow row, bool hovered)
    {
        var rowRect = Rectangle.Inflate(rect, -LogicalToDeviceUnits(2), -LogicalToDeviceUnits(2));
        if (hovered && row.Action is not null)
        {
            using var brush = new SolidBrush(_hover);
            using var path = RoundedRect(rowRect, LogicalToDeviceUnits(6));
            graphics.FillPath(brush, path);
        }

        var textRect = new Rectangle(rowRect.Left + LogicalToDeviceUnits(12), rowRect.Top, rowRect.Width - LogicalToDeviceUnits(24), rowRect.Height);
        if (!string.IsNullOrWhiteSpace(row.Shortcut))
        {
            var shortcutWidth = LogicalToDeviceUnits(row.Shortcut == ">" ? 24 : 96);
            var shortcutRect = new Rectangle(rowRect.Right - shortcutWidth - LogicalToDeviceUnits(12), rowRect.Top, shortcutWidth, rowRect.Height);
            textRect.Width -= shortcutWidth + LogicalToDeviceUnits(18);
            TextRenderer.DrawText(graphics, row.Shortcut, _smallFont, shortcutRect, _secondaryText, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }

        TextRenderer.DrawText(graphics, row.Label, _regularFont, textRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void CloseAfterOutsideClick()
    {
        if (!_hasShown)
        {
            return;
        }

        var leftMouseDown = (Control.MouseButtons & MouseButtons.Left) == MouseButtons.Left;
        if ((DateTime.UtcNow - _shownAt).TotalMilliseconds < 420)
        {
            _wasLeftMouseDown = leftMouseDown;
            return;
        }

        if (leftMouseDown && !_wasLeftMouseDown && !Bounds.Contains(Cursor.Position))
        {
            Close();
        }
        _wasLeftMouseDown = leftMouseDown;
    }

    private void CloseIfSystemSwitcherStarts()
    {
        if (NativeMethods.IsAltPressed())
        {
            Program.Log($"Closing {Text}: Alt/system switcher detected");
            Close();
            return;
        }

        if ((DateTime.UtcNow - _shownAt).TotalMilliseconds < 420)
        {
            return;
        }

        var foreground = NativeMethods.GetForegroundWindowHandle();
        if (_foregroundAtShown != IntPtr.Zero
            && foreground != IntPtr.Zero
            && foreground != Handle
            && foreground != _foregroundAtShown)
        {
            Program.Log($"Closing {Text}: foreground changed");
            Close();
        }
    }

    private static GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_managedResourcesDisposed)
        {
            _managedResourcesDisposed = true;
            _lifetimeCts.Cancel();
            _outsideClickTimer.Dispose();
            _systemSwitchTimer.Dispose();
            _regularFont.Dispose();
            _boldFont.Dispose();
            _smallFont.Dispose();
            _smallBoldFont.Dispose();
            _iconFont.Dispose();
            _lifetimeCts.Dispose();
        }

        base.Dispose(disposing);
    }

    private static void Start(string fileName, string arguments = "")
    {
        Process.Start(new ProcessStartInfo(fileName, arguments) { UseShellExecute = true });
    }

    private static void Confirm(string title, string message, string fileName, string arguments)
    {
        if (MessageBox.Show(message, title, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
        {
            Start(fileName, arguments);
        }
    }

    private static void ToggleDesktop()
    {
        var shellType = Type.GetTypeFromProgID("Shell.Application");
        if (shellType is null) return;
        dynamic? shell = Activator.CreateInstance(shellType);
        shell?.ToggleDesktop();
    }

    private static string GetBatterySummary()
    {
        try
        {
            var status = SystemInformation.PowerStatus;
            if (status.BatteryChargeStatus.HasFlag(BatteryChargeStatus.NoSystemBattery)) return "Plugged in";
            var pct = Math.Round(status.BatteryLifePercent * 100);
            var charging = status.PowerLineStatus == PowerLineStatus.Online ? " - charging" : string.Empty;
            return $"Battery {pct}%{charging}";
        }
        catch
        {
            return "Power status";
        }
    }

    private enum MenuRowKind
    {
        Item,
        Separator,
        Header,
        Card,
        IconCard,
        Slider
    }

    private sealed class MenuRow
    {
        public MenuRow(MenuRowKind kind, string label, string detail, string shortcut, Action? action, int height)
        {
            Kind = kind;
            Label = label;
            Detail = detail;
            Shortcut = shortcut;
            Action = action;
            Height = height;
        }

        public MenuRowKind Kind { get; }

        public string Label { get; set; }

        public string Detail { get; set; }

        public string Shortcut { get; }

        public Action? Action { get; }

        public int Height { get; }

        // IconCard extras: Segoe Fluent icon glyph + accent state (blue chip when active).
        public string Glyph { get; set; } = string.Empty;

        public bool Active { get; set; }

        // Slider extras.
        public SliderInfo? Slider { get; set; }
    }

    private sealed class SliderInfo
    {
        public string Glyph { get; set; } = string.Empty;

        public float Value { get; set; } = 0.5f;

        public Action<float>? OnChange { get; set; }

        public Action<float>? OnCommit { get; set; }
    }
}

internal static class NativeMethods
{
    private static readonly IntPtr HwndTop = IntPtr.Zero;
    private static readonly IntPtr HwndTopMost = new(-1);
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint uFlags);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void ShowWithoutActivation(Form form)
    {
        // Topmost-while-open is the only reliable way for a NO-ACTIVATE popup to appear
        // above the user's active window: HWND_TOP cannot elevate an inactive window over
        // the foreground one, so panels opened BEHIND the app the user was working in
        // (useless). Taking activation is not an option either - Windows' foreground
        // lock denies focus grabs to a background pipe server. The R-04 "lingering over
        // Alt+Tab" hazard is prevented by DISMISSAL, not z-order: the foreground-change
        // timer and Alt detection close the panel the instant any other window takes
        // focus, so the topmost flag never outlives the popup's few seconds on screen.
        ShowWindow(form.Handle, 8); // SW_SHOWNA: show without taking keyboard focus.
        SetWindowPos(form.Handle, HwndTopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate | SwpShowWindow);
    }

    public static bool IsAltPressed()
    {
        const int vkMenu = 0x12;
        var state = GetAsyncKeyState(vkMenu);
        return (state & unchecked((short)0x8000)) != 0 || (state & 0x0001) != 0;
    }

    public static IntPtr GetForegroundWindowHandle()
    {
        return GetForegroundWindow();
    }

    // Windows 11 native rounded corners + dark frame for a borderless popup, so the
    // panels read as system surfaces instead of hard rectangles.
    public static void ApplyRoundedDarkChrome(IntPtr handle)
    {
        try
        {
            var dark = 1;
            DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int)); // DWMWA_USE_IMMERSIVE_DARK_MODE
            var corner = 2;
            DwmSetWindowAttribute(handle, 33, ref corner, sizeof(int)); // DWMWA_WINDOW_CORNER_PREFERENCE = ROUND
            var border = 0x00463F3A; // subtle dark border (COLORREF, BGR)
            DwmSetWindowAttribute(handle, 34, ref border, sizeof(int)); // DWMWA_BORDER_COLOR
        }
        catch
        {
            // Cosmetic only; never let chrome styling break the menu.
        }
    }
}

// Master-volume control over Core Audio (IAudioEndpointVolume) so the Control Center
// sound slider drives the real system volume with no shelling out.
internal static class VolumeService
{
    private static IAudioEndpointVolume? _endpoint;

    public static float? GetMasterVolume()
    {
        try
        {
            // The default output can change while the resident host keeps running.
            // Refresh when a new Control Center is created so the slider never keeps
            // controlling an old HDMI/headset endpoint.
            ReleaseEndpoint();
            Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out var level));
            return level;
        }
        catch (Exception ex)
        {
            Program.Log("Volume read failed: " + ex);
            ReleaseEndpoint();
            return null;
        }
    }

    public static void SetMasterVolume(float level)
    {
        level = Math.Clamp(level, 0f, 1f);
        try
        {
            var context = Guid.Empty;
            Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(level, ref context));
        }
        catch (Exception first)
        {
            // Endpoint changes and device sleep can invalidate the cached COM object.
            // Refresh once and retry before surfacing the failure in the diagnostic log.
            ReleaseEndpoint();
            try
            {
                var context = Guid.Empty;
                Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(level, ref context));
            }
            catch (Exception retry)
            {
                Program.Log($"Volume write failed at {level:P0}: {first}; retry: {retry}");
                ReleaseEndpoint();
            }
        }
    }

    private static IAudioEndpointVolume Endpoint()
    {
        if (_endpoint is not null) return _endpoint;
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        try
        {
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out var device)); // eRender, eMultimedia
            try
            {
                var iid = typeof(IAudioEndpointVolume).GUID;
                Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out var obj)); // CLSCTX_ALL
                _endpoint = (IAudioEndpointVolume)obj;
                return _endpoint;
            }
            finally
            {
                Marshal.FinalReleaseComObject(device);
            }
        }
        finally
        {
            Marshal.FinalReleaseComObject(enumerator);
        }
    }

    private static void ReleaseEndpoint()
    {
        if (_endpoint is null) return;
        try
        {
            Marshal.FinalReleaseComObject(_endpoint);
        }
        catch
        {
            // A disconnected endpoint can already have released its COM wrapper.
        }
        finally
        {
            _endpoint = null;
        }
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumeratorComObject
    {
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig]
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);

        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        [PreserveSig]
        int RegisterControlChangeNotify(IntPtr notify);

        [PreserveSig]
        int UnregisterControlChangeNotify(IntPtr notify);

        [PreserveSig]
        int GetChannelCount(out uint count);

        [PreserveSig]
        int SetMasterVolumeLevel(float levelDb, ref Guid eventContext);

        [PreserveSig]
        int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);

        [PreserveSig]
        int GetMasterVolumeLevel(out float levelDb);

        [PreserveSig]
        int GetMasterVolumeLevelScalar(out float level);
    }
}
