using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.IO.Pipes;
using System.Text;

namespace MacMakeover.MenuBar;

internal enum BarAction
{
    Apple,
    Network,
    Bluetooth,
    Volume,
    ControlCenter,
    Notifications,
    Calendar
}

internal sealed class MenuBarForm : Form
{
    private const int LogicalHeight = 20;
    private readonly Screen _screen;
    private readonly SystemStateProvider _state;
    private readonly bool _preview;
    private readonly List<(Rectangle Bounds, BarAction Action)> _hits = [];
    private readonly Typography _typography;
    private readonly Font _textFont;
    private readonly Font _semiboldFont;
    private readonly Font _smallFont;
    private readonly Font _iconFont;
    private readonly System.Windows.Forms.Timer _dockZOrderTimer;
    private Image? _appleMark;
    private uint _appBarCallback;
    private readonly uint _taskbarCreatedMessage;
    private bool _appBarRegistered;
    private BarAction? _hovered;

    public MenuBarForm(Screen screen, SystemStateProvider state, bool preview)
    {
        _screen = screen;
        _state = state;
        _preview = preview;
        _typography = new Typography();
        _textFont = _typography.Text;
        _semiboldFont = _typography.Emphasis;
        _smallFont = _typography.Telemetry;
        _iconFont = _typography.Icon;
        AppLog.Write($"Typography text={_textFont.Name}; emphasis={_semiboldFont.Name}; telemetry={_smallFont.Name}");
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(24, 27, 32);
        Text = $"MacMakeover Menu Bar ({screen.DeviceName})";
        _taskbarCreatedMessage = NativeMethods.RegisterWindowMessage("TaskbarCreated");
        _dockZOrderTimer = new System.Windows.Forms.Timer { Interval = 100 };
        _dockZOrderTimer.Tick += (_, _) => EnsureNativeDockZOrder();
        Location = preview
            ? new Point(screen.Bounds.Left, screen.Bounds.Top + 80)
            : screen.Bounds.Location;
        Width = screen.Bounds.Width;
        Height = LogicalHeight;

        var asset = Path.Combine(AppContext.BaseDirectory, "Assets", "apple-mark.png");
        if (File.Exists(asset))
        {
            using var source = Image.FromFile(asset);
            _appleMark = new Bitmap(source);
        }

        _state.Changed += OnStateChanged;
        MouseMove += OnMouseMove;
        MouseLeave += (_, _) => { _hovered = null; Invalidate(); };
        MouseUp += OnMouseUp;
        MouseWheel += OnMouseWheel;
        Shown += (_, _) =>
        {
            if (_preview)
            {
                ApplyNativeBounds(new Rectangle(
                    _screen.Bounds.Left,
                    _screen.Bounds.Top + Scale(52),
                    _screen.Bounds.Width,
                    Scale(LogicalHeight)));
            }
            else
            {
                PositionAppBar();
            }
            EnsureTopmost();
            if (!_preview)
            {
                EnsureNativeDockZOrder();
                _dockZOrderTimer.Start();
            }
            AppLog.Write($"Shown {_screen.DeviceName} preview={_preview} bounds={Bounds} dpi={DeviceDpi}");
        };
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate;
            return parameters;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        NativeChrome.ApplyDarkChrome(Handle);
        if (_preview)
        {
            var height = Scale(LogicalHeight);
            ApplyNativeBounds(new Rectangle(
                _screen.Bounds.Left,
                _screen.Bounds.Top + Scale(52),
                _screen.Bounds.Width,
                height));
            return;
        }
        RegisterAppBar();
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        _dockZOrderTimer.Stop();
        RemoveAppBar();
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message message)
    {
        if (!_preview && _taskbarCreatedMessage != 0 && message.Msg == _taskbarCreatedMessage)
        {
            _appBarRegistered = false;
            RegisterAppBar();
        }
        if (_appBarCallback != 0 && message.Msg == _appBarCallback && message.WParam.ToInt32() == NativeMethods.AbnPosChanged)
        {
            PositionAppBar();
        }
        base.WndProc(ref message);
    }

    private void RegisterAppBar()
    {
        if (_appBarRegistered) return;
        _appBarCallback = NativeMethods.RegisterWindowMessage($"MacMakeover.MenuBar.{Handle}");
        var data = CreateAppBarData();
        data.CallbackMessage = _appBarCallback;
        NativeMethods.SHAppBarMessage(NativeMethods.AbmNew, ref data);
        _appBarRegistered = true;
        PositionAppBar();
        AppLog.Write($"Registered appbar {_screen.DeviceName} bounds={Bounds} dpi={DeviceDpi}");
    }

    private void PositionAppBar()
    {
        if (!_appBarRegistered || IsDisposed) return;
        var height = Scale(LogicalHeight);
        var data = CreateAppBarData();
        data.Edge = NativeMethods.AbeTop;
        data.Bounds = new NativeMethods.Rect
        {
            Left = _screen.Bounds.Left,
            Top = _screen.Bounds.Top,
            Right = _screen.Bounds.Right,
            Bottom = _screen.Bounds.Top + height
        };
        NativeMethods.SHAppBarMessage(NativeMethods.AbmQueryPos, ref data);
        data.Bounds.Top = _screen.Bounds.Top;
        data.Bounds.Bottom = data.Bounds.Top + height;
        NativeMethods.SHAppBarMessage(NativeMethods.AbmSetPos, ref data);
        var bounds = data.Bounds.ToRectangle();
        ApplyNativeBounds(bounds);
    }

    private void ApplyNativeBounds(Rectangle bounds)
    {
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HwndTopMost,
            bounds.Left,
            bounds.Top,
            bounds.Width,
            bounds.Height,
            NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow);
    }

    private NativeMethods.AppBarData CreateAppBarData() => new()
    {
        Size = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.AppBarData>(),
        Window = Handle
    };

    private void RemoveAppBar()
    {
        if (!_appBarRegistered || Handle == IntPtr.Zero) return;
        var data = CreateAppBarData();
        NativeMethods.SHAppBarMessage(NativeMethods.AbmRemove, ref data);
        _appBarRegistered = false;
    }

    private void OnStateChanged(object? sender, EventArgs e)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(new Action(Invalidate)); }
        catch (InvalidOperationException) { }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        var client = ClientRectangle;
        using (var background = new SolidBrush(Color.FromArgb(255, 24, 27, 32)))
        {
            e.Graphics.FillRectangle(background, client);
        }
        using (var topLine = new Pen(Color.FromArgb(24, 255, 255, 255), 1F))
        {
            e.Graphics.DrawLine(topLine, 0, 0, Width, 0);
        }
        using (var bottomLine = new Pen(Color.FromArgb(92, 125, 135, 149), Math.Max(1, ScaleValue(0.55F))))
        {
            e.Graphics.DrawLine(bottomLine, 0, Height - 1, Width, Height - 1);
        }

        _hits.Clear();
        var snapshot = _state.Snapshot;
        var leftEnd = DrawLeft(e.Graphics, snapshot);
        var rightStart = DrawRight(e.Graphics, snapshot);
        DrawCenter(e.Graphics, snapshot, leftEnd, rightStart);
    }

    private int DrawLeft(Graphics graphics, SystemSnapshot snapshot)
    {
        var x = Scale(8);
        var appleRect = new Rectangle(x, 0, Scale(26), Height);
        DrawHover(graphics, appleRect, BarAction.Apple);
        if (_appleMark is not null)
        {
            var icon = Scale(14);
            graphics.DrawImage(_appleMark, x + (appleRect.Width - icon) / 2, (Height - icon) / 2, icon, icon);
        }
        else
        {
            DrawCenteredText(graphics, "A", _semiboldFont, appleRect, Color.White);
        }
        _hits.Add((appleRect, BarAction.Apple));
        x = appleRect.Right + Scale(3);

        var maxWidth = Math.Min(Scale(240), Math.Max(Scale(80), Width / 5));
        var appSize = TextRenderer.MeasureText(snapshot.ActiveApp, _semiboldFont, new Size(maxWidth, Height),
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
        var appRect = new Rectangle(x, 0, Math.Min(maxWidth, appSize.Width + Scale(6)), Height);
        TextRenderer.DrawText(
            graphics,
            snapshot.ActiveApp,
            _semiboldFont,
            appRect,
            Color.FromArgb(244, 248, 252),
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
            TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
        return appRect.Right + Scale(10);
    }

    private int DrawRight(Graphics graphics, SystemSnapshot snapshot)
    {
        var x = Width - Scale(8);
        x = DrawRightItem(graphics, x, "\uEA8F", _iconFont, BarAction.Notifications, Scale(28));
        var dateText = DateTime.Now.ToString("ddd d MMM HH:mm");
        var dateWidth = TextRenderer.MeasureText(dateText, _textFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(12);
        x = DrawRightItem(graphics, x, dateText, _textFont, BarAction.Calendar, dateWidth);
        x = DrawRightItem(graphics, x, "\uE713", _iconFont, BarAction.ControlCenter, Scale(28));
        x = DrawRightItem(graphics, x, "\uE767", _iconFont, BarAction.Volume, Scale(28));
        x = DrawRightItem(graphics, x, "\uE702", _iconFont, BarAction.Bluetooth, Scale(27));
        x = DrawRightItem(graphics, x, ConnectionGlyph(snapshot.Connection), _iconFont, BarAction.Network, Scale(29));
        return x - Scale(8);
    }

    private int DrawRightItem(Graphics graphics, int right, string text, Font font, BarAction action, int width)
    {
        var rect = new Rectangle(right - width, 0, width, Height);
        DrawHover(graphics, rect, action);
        DrawCenteredText(graphics, text, font, rect, Color.FromArgb(241, 246, 251));
        _hits.Add((rect, action));
        return rect.Left;
    }

    private void DrawCenter(Graphics graphics, SystemSnapshot snapshot, int leftEnd, int rightStart)
    {
        var available = rightStart - leftEnd - Scale(16);
        if (available < Scale(220)) return;

        var candidates = new[]
        {
            new[]
            {
                $"CPU {snapshot.CpuPercent}%",
                $"RAM {snapshot.UsedMemoryGb:0}/{snapshot.TotalMemoryGb:0} GB",
                $"NET \u2193{FormatRate(snapshot.DownloadBytesPerSecond)} \u2191{FormatRate(snapshot.UploadBytesPerSecond)}"
            },
            new[]
            {
                $"{snapshot.CpuPercent}% CPU",
                $"{snapshot.UsedMemoryGb:0}/{snapshot.TotalMemoryGb:0}G",
                $"\u2193{FormatRate(snapshot.DownloadBytesPerSecond)} \u2191{FormatRate(snapshot.UploadBytesPerSecond)}"
            },
            new[] { $"CPU {snapshot.CpuPercent}%", $"RAM {snapshot.UsedMemoryGb:0}G" }
        };
        var battery = $"{snapshot.BatteryPercent}%";
        var batteryWidth = TextRenderer.MeasureText(battery, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(25);
        string[]? segments = null;
        var groupWidth = 0;
        foreach (var candidate in candidates)
        {
            var candidateWidth = candidate.Sum(MeasureTelemetry) +
                                 Math.Max(0, candidate.Length) * Scale(17) + batteryWidth;
            if (candidateWidth > available) continue;
            segments = candidate;
            groupWidth = candidateWidth;
            break;
        }
        if (segments is null) return;

        var minimumX = leftEnd + Scale(8);
        var maximumX = rightStart - groupWidth - Scale(8);
        if (maximumX < minimumX) return;
        var x = Math.Clamp((Width - groupWidth) / 2, minimumX, maximumX);
        foreach (var segment in segments)
        {
            var width = MeasureTelemetry(segment);
            var textRect = new Rectangle(x, 0, width, Height);
            TextRenderer.DrawText(graphics, segment, _smallFont, textRect, Color.FromArgb(228, 233, 239),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.NoPadding);
            x += width + Scale(8);
            DrawTelemetrySeparator(graphics, x);
            x += Scale(9);
        }

        DrawBattery(graphics, new Rectangle(x, 0, batteryWidth, Height), snapshot.BatteryPercent, snapshot.Charging, battery);
    }

    private int MeasureTelemetry(string text) =>
        TextRenderer.MeasureText(text, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width;

    private void DrawTelemetrySeparator(Graphics graphics, int x)
    {
        using var pen = new Pen(Color.FromArgb(68, 186, 195, 205), Math.Max(1F, ScaleValue(0.5F)));
        graphics.DrawLine(pen, x, Scale(5), x, Height - Scale(5));
    }

    private void DrawBattery(Graphics graphics, Rectangle area, int percent, bool charging, string label)
    {
        var iconWidth = Scale(15);
        var iconHeight = Scale(7);
        var iconX = area.Left + Scale(1);
        var iconY = area.Top + (area.Height - iconHeight) / 2;
        var batteryRect = new Rectangle(iconX, iconY, iconWidth - Scale(2), iconHeight);
        var color = charging || percent >= 20
            ? Color.FromArgb(79, 224, 120)
            : Color.FromArgb(255, 100, 92);
        using var pen = new Pen(color, Math.Max(1, ScaleValue(1F)));
        using var fill = new SolidBrush(color);
        graphics.DrawRectangle(pen, batteryRect);
        graphics.FillRectangle(fill, batteryRect.Right + Scale(1), batteryRect.Top + Scale(2), Scale(2), Math.Max(1, batteryRect.Height - Scale(4)));
        var fillWidth = Math.Max(1, (batteryRect.Width - Scale(2)) * percent / 100);
        graphics.FillRectangle(fill, batteryRect.Left + Scale(1), batteryRect.Top + Scale(1), fillWidth, Math.Max(1, batteryRect.Height - Scale(2)));
        if (charging)
        {
            DrawCenteredText(graphics, "\u26A1", _smallFont, batteryRect, Color.White);
        }
        var labelRect = new Rectangle(batteryRect.Right + Scale(6), area.Top, area.Right - batteryRect.Right - Scale(6), area.Height);
        TextRenderer.DrawText(graphics, label, _smallFont, labelRect, color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }

    private void DrawHover(Graphics graphics, Rectangle rect, BarAction action)
    {
        if (_hovered != action) return;
        var inset = Rectangle.Inflate(rect, -Scale(2), -Scale(3));
        using var brush = new SolidBrush(Color.FromArgb(34, 255, 255, 255));
        using var path = RoundedRectangle(inset, Scale(4));
        graphics.FillPath(brush, path);
    }

    private static GraphicsPath RoundedRectangle(Rectangle rectangle, float radius)
    {
        var diameter = Math.Max(2, radius * 2);
        var path = new GraphicsPath();
        path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static void DrawCenteredText(Graphics graphics, string text, Font font, Rectangle rect, Color color)
    {
        TextRenderer.DrawText(graphics, text, font, rect, color,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }

    private static string ConnectionGlyph(ConnectionKind kind) => kind switch
    {
        ConnectionKind.Vpn => "\uE705",
        ConnectionKind.Wifi => "\uE701",
        ConnectionKind.Ethernet => "\uE839",
        ConnectionKind.Tethered => "\uE717",
        _ => "\uF384"
    };

    private static string FormatRate(long bytesPerSecond)
    {
        if (bytesPerSecond >= 1024L * 1024L) return $"{bytesPerSecond / 1024d / 1024d:0.0}M";
        if (bytesPerSecond >= 1024L) return $"{bytesPerSecond / 1024d:0}K";
        return $"{bytesPerSecond}B";
    }

    private void OnMouseMove(object? sender, MouseEventArgs e)
    {
        var hovered = _hits.FirstOrDefault(hit => hit.Bounds.Contains(e.Location)).Action;
        BarAction? next = _hits.Any(hit => hit.Bounds.Contains(e.Location)) ? hovered : null;
        if (_hovered == next) return;
        _hovered = next;
        Cursor = next is null ? Cursors.Default : Cursors.Hand;
        Invalidate();
    }

    private void OnMouseUp(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        if (e.X <= Scale(2) || e.X >= Width - Scale(2))
        {
            MenuRouter.Send("desktop");
            return;
        }

        var hit = _hits.Where(item => item.Bounds.Contains(e.Location))
            .Select(item => (BarAction?)item.Action)
            .FirstOrDefault();
        switch (hit)
        {
            case BarAction.Apple:
                MenuRouter.Send("apple");
                break;
            case BarAction.Network:
                MenuRouter.Send("network");
                break;
            case BarAction.Bluetooth:
                MenuRouter.Send("bluetooth");
                break;
            case BarAction.Volume:
            case BarAction.ControlCenter:
                MenuRouter.Send("control");
                break;
            case BarAction.Notifications:
            case BarAction.Calendar:
                MenuRouter.OpenNotifications();
                break;
        }
    }

    private void OnMouseWheel(object? sender, MouseEventArgs e)
    {
        var hit = _hits.Where(item => item.Bounds.Contains(e.Location))
            .Select(item => (BarAction?)item.Action)
            .FirstOrDefault();
        if (hit != BarAction.Volume) return;
        var foreground = NativeMethods.GetForegroundWindow();
        var command = e.Delta > 0 ? NativeMethods.AppCommandVolumeUp : NativeMethods.AppCommandVolumeDown;
        NativeMethods.SendMessage(foreground, NativeMethods.WmAppCommand, foreground, (IntPtr)(command << 16));
    }

    private void EnsureTopmost()
    {
        const int vkMenu = 0x12;
        if ((NativeMethods.GetAsyncKeyState(vkMenu) & 0x8000) != 0) return;
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HwndTopMost,
            0,
            0,
            0,
            0,
            NativeMethods.SwpNoMove | NativeMethods.SwpNoSize |
            NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow);
    }

    private void EnsureNativeDockZOrder()
    {
        const int vkMenu = 0x12;
        if (_preview || (NativeMethods.GetAsyncKeyState(vkMenu) & 0x8000) != 0) return;

        var taskbar = NativeMethods.FindTaskbarFor(_screen.Bounds);
        if (taskbar == IntPtr.Zero) return;

        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground != IntPtr.Zero && NativeMethods.IsBorderlessFullscreen(foreground, _screen.Bounds))
        {
            return;
        }

        var extendedStyle = NativeMethods.GetWindowLongPtr(taskbar, NativeMethods.GwlExStyle).ToInt64();
        if ((extendedStyle & NativeMethods.WsExTopMost) != 0) return;

        if (NativeMethods.SetWindowPos(
                taskbar,
                NativeMethods.HwndTopMost,
                0,
                0,
                0,
                0,
                NativeMethods.SwpNoMove | NativeMethods.SwpNoSize |
                NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow))
        {
            AppLog.Write($"Restored native dock topmost {_screen.DeviceName}");
        }
    }

    private int Scale(int logical) => Math.Max(1, (int)Math.Round(logical * DeviceDpi / 96d));
    private float ScaleValue(float logical) => Math.Max(1F, logical * DeviceDpi / 96F);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _state.Changed -= OnStateChanged;
            _dockZOrderTimer.Dispose();
            _appleMark?.Dispose();
            _typography.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal static class MenuRouter
{
    private const string PipeName = "MacMakeover.MenuHost";

    public static void Send(string command)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(120);
            using var writer = new StreamWriter(client, Encoding.UTF8) { AutoFlush = true };
            writer.WriteLine(command);
            return;
        }
        catch
        {
            // Start the resident host only when its pipe is genuinely unavailable.
        }

        var host = Path.Combine(AppContext.BaseDirectory, "MacMakeover.MenuHost.exe");
        if (!File.Exists(host))
        {
            host = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "MacMakeover.MenuHost", "MacMakeover.MenuHost.exe"));
        }
        if (File.Exists(host))
        {
            Process.Start(new ProcessStartInfo(host, $"--show {command}") { UseShellExecute = false, CreateNoWindow = true });
        }
    }

    public static void OpenNotifications()
    {
        try
        {
            Process.Start(new ProcessStartInfo("macmakeover-notification-center:") { UseShellExecute = true });
        }
        catch
        {
            Process.Start(new ProcessStartInfo("ms-actioncenter:") { UseShellExecute = true });
        }
    }
}

internal static class NativeChrome
{
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    public static void ApplyDarkChrome(IntPtr handle)
    {
        try
        {
            var enabled = 1;
            DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int));
            var corner = 1; // DWMWCP_DONOTROUND
            DwmSetWindowAttribute(handle, 33, ref corner, sizeof(int));
        }
        catch
        {
            // Cosmetic only.
        }
    }
}
