using Microsoft.Win32;
using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace MacMakeover.Dock;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Any(value => value.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                var apps = PinnedApp.Load();
                if (apps.Count != 21) { Environment.ExitCode = 2; return; }
                foreach (var app in apps)
                {
                    using var icon = app.LoadIcon(56);
                    if (icon is null) { Environment.ExitCode = 3; return; }
                }
                Environment.ExitCode = 0;
            }
            catch { Environment.ExitCode = 4; }
            return;
        }
        if (args.Any(value => value.Equals("--shutdown", StringComparison.OrdinalIgnoreCase)))
        {
            try { EventWaitHandle.OpenExisting("Local\\MacMakeover.Dock.Exit").Set(); } catch (WaitHandleCannotBeOpenedException) { }
            return;
        }
        var preview = args.Any(value => value.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        using var mutex = new Mutex(true, preview ? "Local\\MacMakeover.Dock.Preview" : "Local\\MacMakeover.Dock", out var first);
        if (!first) return;
        using var exit = new EventWaitHandle(false, EventResetMode.AutoReset, preview ? "Local\\MacMakeover.Dock.Preview.Exit" : "Local\\MacMakeover.Dock.Exit");
        ApplicationConfiguration.Initialize();
        Application.Run(new DockContext(preview, exit));
    }
}

internal sealed class DockContext : ApplicationContext
{
    private readonly bool _preview;
    private readonly List<DockForm> _forms = [];
    private readonly List<WorkAreaGapForm> _gapForms = [];
    private readonly List<DockBackdropForm> _backdropForms = [];
    private readonly List<IntPtr> _taskbars = [];
    private readonly System.Windows.Forms.Timer _taskbarGuard = new() { Interval = 1500 };
    private readonly RegisteredWaitHandle _exitRegistration;
    private bool _rebuilding;
    private int _displayRebuildPending;
    private bool _exiting;

    public DockContext(bool preview, EventWaitHandle exit)
    {
        _preview = preview;
        if (!preview)
        {
            HideWindowsTaskbars();
            _taskbarGuard.Tick += (_, _) => HideWindowsTaskbars();
            _taskbarGuard.Start();
        }
        SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
        BuildForms();
        _exitRegistration = ThreadPool.RegisterWaitForSingleObject(exit, (_, _) =>
        {
            var dispatcher = _forms.FirstOrDefault(form => form.IsHandleCreated && !form.IsDisposed);
            if (dispatcher is not null) dispatcher.BeginInvoke(new Action(ExitThread));
        }, null, Timeout.Infinite, true);
    }

    private void BuildForms()
    {
        var apps = PinnedApp.Load();
        foreach (var screen in _preview ? Screen.AllScreens.Where(s => s.Primary) : Screen.AllScreens)
        {
            if (!_preview)
            {
                var gapForm = new WorkAreaGapForm(screen);
                _gapForms.Add(gapForm);
                gapForm.Show();
                var backdropForm = new DockBackdropForm(screen);
                _backdropForms.Add(backdropForm);
                backdropForm.Show();
            }
            var form = new DockForm(screen, apps, _preview);
            form.FormClosed += (_, _) => { _forms.Remove(form); if (!_rebuilding && !_exiting && _forms.Count == 0) ExitThread(); };
            _forms.Add(form);
            form.Show();
        }
        if (!_preview) HideWindowsTaskbars();
    }

    private void OnDisplayChanged(object? sender, EventArgs e)
    {
        if (_exiting) return;
        var dispatcher = _forms.FirstOrDefault(form => form.IsHandleCreated && !form.IsDisposed);
        if (dispatcher is not null && dispatcher.InvokeRequired)
        {
            if (Interlocked.Exchange(ref _displayRebuildPending, 1) != 0) return;
            try
            {
                dispatcher.BeginInvoke(new Action(() =>
                {
                    Interlocked.Exchange(ref _displayRebuildPending, 0);
                    OnDisplayChanged(sender, e);
                }));
            }
            catch (InvalidOperationException) { Interlocked.Exchange(ref _displayRebuildPending, 0); }
            return;
        }
        if (_rebuilding) return;
        _rebuilding = true;
        try
        {
            foreach (var form in _forms.ToArray()) form.Close();
            _forms.Clear();
            foreach (var gapForm in _gapForms.ToArray()) gapForm.Close();
            _gapForms.Clear();
            foreach (var backdropForm in _backdropForms.ToArray()) backdropForm.Close();
            _backdropForms.Clear();
            BuildForms();
        }
        finally { _rebuilding = false; }
    }

    private void HideWindowsTaskbars()
    {
        NativeMethods.EnumWindows((window, _) =>
        {
            var name = new System.Text.StringBuilder(64);
            NativeMethods.GetClassName(window, name, name.Capacity);
            if (name.ToString() is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")
            {
                if (!_taskbars.Contains(window)) _taskbars.Add(window);
                if (NativeMethods.IsWindowVisible(window)) NativeMethods.ShowWindow(window, NativeMethods.SwHide);
            }
            return true;
        }, IntPtr.Zero);
    }

    protected override void ExitThreadCore()
    {
        if (_exiting) return;
        _exiting = true;
        SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
        _exitRegistration.Unregister(null);
        _taskbarGuard.Stop();
        _taskbarGuard.Dispose();
        foreach (var form in _forms.ToArray()) form.Dispose();
        foreach (var gapForm in _gapForms.ToArray()) gapForm.Dispose();
        foreach (var backdropForm in _backdropForms.ToArray()) backdropForm.Dispose();
        foreach (var taskbar in _taskbars) NativeMethods.ShowWindow(taskbar, NativeMethods.SwShow);
        base.ExitThreadCore();
    }
}

internal sealed class WorkAreaGapForm : Form
{
    private const int LogicalGap = 8;
    private const int WmNcHitTest = 0x0084;
    private static readonly IntPtr HtTransparent = new(-1);
    private readonly Screen _screen;
    private readonly uint _callbackMessage;
    private bool _registered;

    public WorkAreaGapForm(Screen screen)
    {
        _screen = screen;
        _callbackMessage = NativeMethods.RegisterWindowMessage($"MacMakeover.Dock.WorkAreaGap.{Environment.ProcessId}.{screen.DeviceName}");
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        Enabled = false;
        Opacity = 0.999;
        BackColor = Color.FromArgb(16, 18, 28);
        DoubleBuffered = true;
        Location = new Point(screen.Bounds.Left, screen.Bounds.Bottom - 1);
        Size = new Size(1, 1);
        Shown += (_, _) => RegisterAndPosition();
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate |
                NativeMethods.WsExTransparent | NativeMethods.WsExLayered;
            return cp;
        }
    }

    private NativeMethods.AppBarData CreateAppBarData() => new()
    {
        Size = Marshal.SizeOf<NativeMethods.AppBarData>(),
        Window = Handle,
        CallbackMessage = _callbackMessage,
        Edge = NativeMethods.AbeBottom
    };

    private void RegisterAndPosition()
    {
        var data = CreateAppBarData();
        _registered = NativeMethods.SHAppBarMessage(NativeMethods.AbmNew, ref data) != UIntPtr.Zero;
        if (!_registered) return;

        var gap = (int)Math.Round(LogicalGap * DeviceDpi / 96f);
        data.Bounds = new NativeMethods.Rect
        {
            Left = _screen.Bounds.Left,
            Top = _screen.Bounds.Top,
            Right = _screen.Bounds.Right,
            Bottom = _screen.Bounds.Bottom
        };
        NativeMethods.SHAppBarMessage(NativeMethods.AbmQueryPos, ref data);
        data.Bounds.Top = data.Bounds.Bottom - gap;
        NativeMethods.SHAppBarMessage(NativeMethods.AbmSetPos, ref data);
        Bounds = Rectangle.FromLTRB(data.Bounds.Left, data.Bounds.Top, data.Bounds.Right, data.Bounds.Bottom);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        WallpaperSlice.Draw(e.Graphics, ClientRectangle, _screen.Bounds, Bounds.Top);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmNcHitTest)
        {
            message.Result = HtTransparent;
            return;
        }
        base.WndProc(ref message);
    }

    protected override void Dispose(bool disposing)
    {
        if (_registered && IsHandleCreated)
        {
            var data = CreateAppBarData();
            NativeMethods.SHAppBarMessage(NativeMethods.AbmRemove, ref data);
            _registered = false;
        }
        base.Dispose(disposing);
    }
}

internal sealed class DockBackdropForm : Form
{
    private const int LogicalHeight = 48;
    private const int WmNcHitTest = 0x0084;
    private static readonly IntPtr HtTransparent = new(-1);
    private readonly Screen _screen;

    public DockBackdropForm(Screen screen)
    {
        _screen = screen;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        Enabled = false;
        Opacity = 0.999;
        BackColor = Color.FromArgb(16, 18, 28);
        DoubleBuffered = true;
        Shown += (_, _) => PositionBackdrop();
        DpiChanged += (_, _) => BeginInvoke(new Action(PositionBackdrop));
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate |
                NativeMethods.WsExTransparent | NativeMethods.WsExLayered;
            return cp;
        }
    }

    private void PositionBackdrop()
    {
        var height = (int)Math.Round(LogicalHeight * DeviceDpi / 96f);
        Bounds = new Rectangle(_screen.Bounds.Left, _screen.Bounds.Bottom - height, _screen.Bounds.Width, height);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        WallpaperSlice.Draw(e.Graphics, ClientRectangle, _screen.Bounds, Bounds.Top);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmNcHitTest)
        {
            message.Result = HtTransparent;
            return;
        }
        base.WndProc(ref message);
    }
}

internal sealed class DockForm : Form
{
    private const int LogicalHeight = 48;
    private const int SlotWidth = 44;
    private const int IconSize = 28;
    private const int HorizontalPadding = 22;
    private readonly Screen _screen;
    private readonly bool _preview;
    private readonly FlowLayoutPanel _items;
    private readonly System.Windows.Forms.Timer _stateTimer = new() { Interval = 3000 };
    private Rectangle _frame;

    public DockForm(Screen screen, IReadOnlyList<PinnedApp> apps, bool preview)
    {
        _screen = screen;
        _preview = preview;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(16, 18, 28);
        DoubleBuffered = true;
        _items = new FlowLayoutPanel
        {
            BackColor = Color.Transparent,
            WrapContents = false,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = Padding.Empty,
            Padding = Padding.Empty,
            AutoSize = false
        };
        Controls.Add(_items);
        var tips = new ToolTip { InitialDelay = 450, ReshowDelay = 100, AutoPopDelay = 5000 };
        foreach (var app in apps)
        {
            var button = new DockButton(app, IconSize) { Width = SlotWidth, Height = 48, Margin = Padding.Empty };
            tips.SetToolTip(button, app.Name);
            _items.Controls.Add(button);
        }
        Shown += (_, _) =>
        {
            Location = _screen.Bounds.Location;
            BeginInvoke(new Action(PositionDock));
        };
        DpiChanged += (_, _) => BeginInvoke(new Action(PositionDock));
        _stateTimer.Tick += (_, _) =>
        {
            var running = SnapshotProcesses();
            foreach (DockButton button in _items.Controls) button.RefreshState(running);
        };
        _stateTimer.Start();
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ExStyle |= NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate; return cp; } }

    private void PositionDock()
    {
        var scale = DeviceDpi / 96f;
        var height = (int)Math.Round(LogicalHeight * scale);
        Location = new Point(_screen.Bounds.Left, _screen.Bounds.Bottom - height);
        Size = new Size(_screen.Bounds.Width, height);
        var contentWidth = _items.Controls.Count * (int)Math.Round(SlotWidth * scale);
        var frameWidth = contentWidth + (int)Math.Round(HorizontalPadding * 2 * scale);
        var frameHeight = (int)Math.Round(42 * scale);
        _frame = new Rectangle((Width - frameWidth) / 2, (Height - frameHeight) / 2, frameWidth, frameHeight);
        foreach (DockButton button in _items.Controls)
        {
            button.Width = (int)Math.Round(SlotWidth * scale);
            button.Height = frameHeight - (int)Math.Round(4 * scale);
        }
        _items.Bounds = new Rectangle(_frame.Left + (int)Math.Round(HorizontalPadding * scale), _frame.Top + (int)Math.Round(2 * scale), contentWidth, frameHeight - (int)Math.Round(4 * scale));
        using var path = Rounded(_frame, (int)Math.Round(14 * scale));
        Region = new Region(path);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        WallpaperSlice.Draw(e.Graphics, ClientRectangle, _screen.Bounds, Bounds.Top);
        if (_frame.Width <= 0 || _frame.Height <= 0) return;
        using var framePath = Rounded(_frame, (int)Math.Round(14 * DeviceDpi / 96f));
        using var brush = new LinearGradientBrush(_frame, Color.FromArgb(250, 38, 44, 52), Color.FromArgb(252, 15, 18, 23), LinearGradientMode.Vertical);
        e.Graphics.FillPath(brush, framePath);
        using var top = new Pen(Color.FromArgb(150, 137, 151, 166), Math.Max(1, DeviceDpi / 96f));
        e.Graphics.DrawLine(top, _frame.Left + 15, _frame.Top + 1, _frame.Right - 15, _frame.Top + 1);
        using var edge = new Pen(Color.FromArgb(110, 83, 96, 110), Math.Max(1, DeviceDpi / 96f));
        e.Graphics.DrawArc(edge, _frame.Left, _frame.Top, _frame.Height, _frame.Height, 90, 180);
        e.Graphics.DrawArc(edge, _frame.Right - _frame.Height, _frame.Top, _frame.Height, _frame.Height, 270, 180);
        e.Graphics.DrawLine(edge, _frame.Left + _frame.Height / 2, _frame.Bottom - 1, _frame.Right - _frame.Height / 2, _frame.Bottom - 1);
    }

    private static GraphicsPath Rounded(Rectangle rectangle, int radius)
    {
        var path = new GraphicsPath(); var d = radius * 2;
        path.AddArc(rectangle.Left, rectangle.Top, d, d, 180, 90); path.AddArc(rectangle.Right - d, rectangle.Top, d, d, 270, 90);
        path.AddArc(rectangle.Right - d, rectangle.Bottom - d, d, d, 0, 90); path.AddArc(rectangle.Left, rectangle.Bottom - d, d, d, 90, 90); path.CloseFigure();
        return path;
    }

    private static HashSet<string> SnapshotProcesses()
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var process in Process.GetProcesses())
        {
            try { names.Add(process.ProcessName); }
            catch (InvalidOperationException) { }
            finally { process.Dispose(); }
        }
        return names;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _stateTimer.Dispose();
        base.Dispose(disposing);
    }
}

internal static class WallpaperSlice
{
    private static readonly Image? Wallpaper = LoadWallpaper();

    public static void Draw(Graphics graphics, Rectangle target, Rectangle screenBounds, int absoluteTop)
    {
        if (Wallpaper is null)
        {
            using var fallback = new SolidBrush(Color.FromArgb(16, 18, 28));
            graphics.FillRectangle(fallback, target);
            return;
        }

        var scale = Math.Max(screenBounds.Width / (double)Wallpaper.Width, screenBounds.Height / (double)Wallpaper.Height);
        var scaledWidth = Wallpaper.Width * scale;
        var scaledHeight = Wallpaper.Height * scale;
        var cropX = (scaledWidth - screenBounds.Width) / 2d;
        var cropY = (scaledHeight - screenBounds.Height) / 2d;
        var relativeTop = absoluteTop - screenBounds.Top;
        var source = new RectangleF(
            (float)(cropX / scale),
            (float)((cropY + relativeTop) / scale),
            (float)(target.Width / scale),
            (float)(target.Height / scale));
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        graphics.DrawImage(Wallpaper, target, source, GraphicsUnit.Pixel);
    }

    private static Image? LoadWallpaper()
    {
        try
        {
            var path = Registry.GetValue(@"HKEY_CURRENT_USER\Control Panel\Desktop", "WallPaper", null) as string;
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
            using var stream = File.OpenRead(path);
            using var source = Image.FromStream(stream);
            return new Bitmap(source);
        }
        catch { return null; }
    }
}

internal sealed class DockButton : Control
{
    private readonly PinnedApp _app;
    private readonly Image? _icon;
    private bool _running;
    private bool _hover;

    public DockButton(PinnedApp app, int iconSize)
    {
        _app = app;
        _icon = app.LoadIcon(iconSize * 2);
        SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        AccessibleName = app.Name;
        TabStop = false;
        MouseEnter += (_, _) => { _hover = true; Invalidate(); };
        MouseLeave += (_, _) => { _hover = false; Invalidate(); };
        Click += (_, _) => _app.ActivateOrLaunch();
    }

    public void RefreshState(IReadOnlySet<string> processes) { var running = _app.IsRunning(processes); if (running != _running) { _running = running; Invalidate(); } }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var scale = DeviceDpi / 96f;
        if (_hover)
        {
            using var hover = new SolidBrush(Color.FromArgb(32, 255, 255, 255));
            using var path = new GraphicsPath();
            var box = Rectangle.Inflate(ClientRectangle, -(int)(3 * scale), -(int)(4 * scale));
            path.AddArc(box.Left, box.Top, 12, 12, 180, 90); path.AddArc(box.Right - 12, box.Top, 12, 12, 270, 90); path.AddArc(box.Right - 12, box.Bottom - 12, 12, 12, 0, 90); path.AddArc(box.Left, box.Bottom - 12, 12, 12, 90, 90); path.CloseFigure();
            e.Graphics.FillPath(hover, path);
        }
        if (_icon != null)
        {
            var size = (int)Math.Round(28 * scale);
            var x = (Width - size) / 2; var y = (Height - size) / 2 - (int)Math.Round(2 * scale);
            e.Graphics.DrawImage(_icon, new Rectangle(x, y, size, size));
        }
        else
        {
            var size = (int)Math.Round(28 * scale);
            var x = (Width - size) / 2; var y = (Height - size) / 2 - (int)Math.Round(2 * scale);
            using var tile = new SolidBrush(Color.FromArgb(255, 57, 66, 78));
            e.Graphics.FillEllipse(tile, x, y, size, size);
            using var font = new Font("Segoe UI Semibold", 9.5f * scale, FontStyle.Bold, GraphicsUnit.Pixel);
            TextRenderer.DrawText(e.Graphics, string.Concat(_app.Name.Where(char.IsLetter).Take(2)).ToUpperInvariant(), font, new Rectangle(x, y, size, size), Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
        if (_running)
        {
            var dot = (int)Math.Round(3 * scale);
            using var brush = new SolidBrush(Color.FromArgb(225, 207, 221, 233));
            e.Graphics.FillEllipse(brush, (Width - dot) / 2, Height - (int)Math.Round(5 * scale), dot, dot);
        }
    }

    protected override void Dispose(bool disposing) { if (disposing) _icon?.Dispose(); base.Dispose(disposing); }
}

internal sealed class PinnedApp
{
    private static readonly Dictionary<string, string[]> Processes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["File Explorer"] = ["explorer"], ["Outlook"] = ["olk"], ["Outlook (classic)"] = ["outlook"],
        ["Microsoft Teams"] = ["ms-teams"], ["ChatGPT"] = ["ChatGPT"], ["Claude"] = ["Claude"],
        ["Brave"] = ["brave"], ["Firefox"] = ["firefox"], ["Google Chrome"] = ["chrome"], ["Cursor"] = ["Cursor"],
        ["Sublime Text"] = ["sublime_text"], ["JetBrains Rider 2026.1.1"] = ["rider64"], ["Visual Studio"] = ["devenv"],
        ["SQL Server Management Studio 22"] = ["Ssms"], ["Microsoft Azure Storage Explorer"] = ["StorageExplorer"],
        ["Service Bus Explorer"] = ["ServiceBusExplorer"], ["PowerShell 7 (x64)"] = ["pwsh"], ["Bruno"] = ["Bruno"],
        ["WireGuard"] = ["wireguard"], ["Proton VPN"] = ["ProtonVPN.Client", "ProtonVPN.Launcher"], ["Bitwarden"] = ["Bitwarden"]
    };
    public required string Name { get; init; }
    public string? AppId { get; init; }
    public required string[] Patterns { get; init; }
    public string? Shortcut { get; init; }

    public static IReadOnlyList<PinnedApp> Load()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "native-taskbar-pins.json")));
        var pinned = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Internet Explorer", "Quick Launch", "User Pinned", "TaskBar");
        return document.RootElement.GetProperty("pins").EnumerateArray().Select(item =>
        {
            var name = item.GetProperty("name").GetString()!;
            var patterns = item.GetProperty("taskbandPatterns").EnumerateArray().Select(p => p.GetString()!).ToArray();
            var shortcut = Directory.Exists(pinned) ? Directory.EnumerateFiles(pinned, "*.lnk").FirstOrDefault(path => patterns.Any(p => Path.GetFileName(path).Contains(Path.GetFileNameWithoutExtension(p), StringComparison.OrdinalIgnoreCase))) : null;
            return new PinnedApp { Name = name, AppId = item.TryGetProperty("appId", out var id) && id.ValueKind != JsonValueKind.Null ? id.GetString() : null, Patterns = patterns, Shortcut = shortcut };
        }).ToArray();
    }

    public bool IsRunning(IReadOnlySet<string> processes) => Processes.GetValueOrDefault(Name, []).Any(processes.Contains);

    public void ActivateOrLaunch()
    {
        foreach (var processName in Processes.GetValueOrDefault(Name, []))
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                if (NativeMethods.IsIconic(process.MainWindowHandle)) NativeMethods.ShowWindow(process.MainWindowHandle, NativeMethods.SwRestore);
                if (NativeMethods.SetForegroundWindow(process.MainWindowHandle)) return;
            }
        }
        var target = Shortcut ?? (AppId is null ? null : $"shell:AppsFolder\\{AppId}");
        if (target is null) return;
        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
    }

    public Image? LoadIcon(int size)
    {
        if (Name.Equals("File Explorer", StringComparison.OrdinalIgnoreCase))
        {
            var explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
            return LoadFileIcon(explorer, size);
        }
        if (AppId is not null && Shortcut is null)
        {
            var packaged = LoadShellItemIcon($"shell:AppsFolder\\{AppId}", size);
            if (packaged is not null) return packaged;
        }
        var source = Shortcut is null ? null : ResolveShortcutTarget(Shortcut);
        source ??= Shortcut;
        source ??= AppId is null ? null : $"shell:AppsFolder\\{AppId}";
        if (source is null) return null;
        return LoadFileIcon(source, size);
    }

    private static Image? LoadFileIcon(string source, int size)
    {
        var result = NativeMethods.SHGetFileInfo(source, 0, out var info, (uint)System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.ShFileInfo>(), NativeMethods.ShgfiIcon | NativeMethods.ShgfiLargeIcon);
        if (result == IntPtr.Zero || info.Icon == IntPtr.Zero) return null;
        try { using var icon = Icon.FromHandle(info.Icon); return new Bitmap(icon.ToBitmap(), new Size(size, size)); }
        finally { NativeMethods.DestroyIcon(info.Icon); }
    }

    private static string? ResolveShortcutTarget(string path)
    {
        object? shell = null; object? shortcut = null;
        try
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type is null) return null;
            shell = Activator.CreateInstance(type);
            shortcut = type.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, [path]);
            var target = shortcut?.GetType().InvokeMember("TargetPath", System.Reflection.BindingFlags.GetProperty, null, shortcut, null) as string;
            return string.IsNullOrWhiteSpace(target) ? null : Environment.ExpandEnvironmentVariables(target);
        }
        catch { return null; }
        finally
        {
            if (shortcut is not null && Marshal.IsComObject(shortcut)) Marshal.FinalReleaseComObject(shortcut);
            if (shell is not null && Marshal.IsComObject(shell)) Marshal.FinalReleaseComObject(shell);
        }
    }

    private static Image? LoadShellItemIcon(string path, int size)
    {
        NativeMethods.IShellItemImageFactory? factory = null;
        try
        {
            var id = typeof(NativeMethods.IShellItemImageFactory).GUID;
            NativeMethods.SHCreateItemFromParsingName(path, IntPtr.Zero, ref id, out factory);
            if (factory.GetImage(new Size(size, size), NativeMethods.ShellImageFlags.IconOnly | NativeMethods.ShellImageFlags.BiggerSizeOk, out var bitmap) != 0 || bitmap == IntPtr.Zero) return null;
            try { using var image = Image.FromHbitmap(bitmap); return new Bitmap(image, new Size(size, size)); }
            finally { NativeMethods.DeleteObject(bitmap); }
        }
        catch { return null; }
        finally { if (factory is not null && Marshal.IsComObject(factory)) Marshal.FinalReleaseComObject(factory); }
    }
}
