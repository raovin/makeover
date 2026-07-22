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
    TrayOverflow,
    Notifications,
    Calendar
}

internal sealed class MenuBarForm : Form
{
    private const int LogicalHeight = 20;
    private const int LogicalCornerHitSize = 8;
    private readonly Screen _screen;
    private readonly SystemStateProvider _state;
    private readonly bool _preview;
    private readonly string? _previewPower;
    private readonly List<(Rectangle Bounds, BarAction Action)> _hits = [];
    private readonly List<(Rectangle Bounds, TrayAppSnapshot App)> _trayHits = [];
    private readonly TrayIconCache _trayIcons = new();
    private readonly ToolTip _toolTip = new() { InitialDelay = 400, ReshowDelay = 100, AutoPopDelay = 5000 };
    private Typography? _typography;
    private Font _textFont = null!;
    private Font _semiboldFont = null!;
    private Font _smallFont = null!;
    private Font _iconFont = null!;
    private Image? _appleMark;
    private uint _appBarCallback;
    private readonly uint _taskbarCreatedMessage;
    private bool _appBarRegistered;
    private BarAction? _hovered;
    private string? _hoveredTrayKey;

    public MenuBarForm(Screen screen, SystemStateProvider state, bool preview, string? previewPower)
    {
        _screen = screen;
        _state = state;
        _preview = preview;
        _previewPower = previewPower;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(24, 27, 32);
        Text = $"MacMakeover Menu Bar ({screen.DeviceName})";
        _taskbarCreatedMessage = NativeMethods.RegisterWindowMessage("TaskbarCreated");
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
        MouseLeave += (_, _) =>
        {
            _hovered = null;
            _hoveredTrayKey = null;
            _toolTip.SetToolTip(this, string.Empty);
            Invalidate();
        };
        MouseUp += OnMouseUp;
        MouseWheel += OnMouseWheel;
        Shown += (_, _) =>
        {
            ConfigureTypography();
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
                RegisterAppBar();
                _ = ReassertAppBarAfterStartupAsync();
            }
            EnsureTopmost();
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
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
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

        if (_typography is null) return;

        _hits.Clear();
        _trayHits.Clear();
        var snapshot = ApplyPowerPreview(_state.Snapshot, _previewPower);
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
        foreach (var app in snapshot.TrayApps.Take(3))
        {
            x = DrawTrayItem(graphics, x, app);
        }
        if (snapshot.TrayApps.Count > 3)
        {
            x = DrawRightItem(graphics, x, "\uE712", _iconFont, BarAction.TrayOverflow, Scale(24));
        }
        return x - Scale(8);
    }

    private int DrawTrayItem(Graphics graphics, int right, TrayAppSnapshot app)
    {
        var width = Scale(24);
        var rect = new Rectangle(right - width, 0, width, Height);
        if (_hoveredTrayKey?.Equals(app.Key, StringComparison.OrdinalIgnoreCase) == true)
        {
            var inset = Rectangle.Inflate(rect, -Scale(2), -Scale(3));
            using var hover = new SolidBrush(Color.FromArgb(34, 255, 255, 255));
            using var path = RoundedRectangle(inset, Scale(4));
            graphics.FillPath(hover, path);
        }
        var image = _trayIcons.Get(app);
        if (image is not null)
        {
            var size = Scale(14);
            graphics.DrawImage(image, rect.Left + (rect.Width - size) / 2, (Height - size) / 2, size, size);
        }
        else
        {
            DrawCenteredText(graphics, app.Name[..1].ToUpperInvariant(), _smallFont, rect, Color.FromArgb(241, 246, 251));
        }
        _trayHits.Add((rect, app));
        return rect.Left;
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
        var battery = PowerSourceLabel(snapshot);
        var powerMode = PowerModeLabel(snapshot.PowerMode);
        // Keep a permanent slot between the battery and its label so AC status never
        // shifts the rest of the centered telemetry group when power is connected.
        var batteryWidth = TextRenderer.MeasureText(battery, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(34);
        var powerModeWidth = TextRenderer.MeasureText(powerMode, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(6);
        string[]? segments = null;
        var groupWidth = 0;
        foreach (var candidate in candidates)
        {
            var candidateWidth = candidate.Sum(MeasureTelemetry) +
                                 Math.Max(0, candidate.Length) * Scale(17) + batteryWidth +
                                 Scale(17) + powerModeWidth;
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

        DrawBattery(graphics, new Rectangle(x, 0, batteryWidth, Height), snapshot, battery);
        x += batteryWidth + Scale(8);
        DrawTelemetrySeparator(graphics, x);
        x += Scale(9);
        DrawPowerMode(graphics, new Rectangle(x, 0, powerModeWidth, Height), snapshot.PowerMode, powerMode);
    }

    private int MeasureTelemetry(string text) =>
        TextRenderer.MeasureText(text, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width;

    private void DrawTelemetrySeparator(Graphics graphics, int x)
    {
        using var pen = new Pen(Color.FromArgb(68, 186, 195, 205), Math.Max(1F, ScaleValue(0.5F)));
        graphics.DrawLine(pen, x, Scale(5), x, Height - Scale(5));
    }

    private void DrawBattery(Graphics graphics, Rectangle area, SystemSnapshot snapshot, string label)
    {
        var percent = snapshot.BatteryPercent;
        var iconWidth = Scale(17);
        var iconHeight = Scale(9);
        var iconX = area.Left + Scale(1);
        var iconY = area.Top + (area.Height - iconHeight) / 2;
        var batteryRect = new Rectangle(iconX, iconY, iconWidth - Scale(2), iconHeight);
        var color = snapshot.OnAcPower
            ? Color.FromArgb(79, 224, 120)
            : percent < 20 || snapshot.PowerMode == PowerModeKind.Saver
                ? Color.FromArgb(247, 190, 80)
                : Color.FromArgb(220, 228, 236);
        using var pen = new Pen(color, Math.Max(1, ScaleValue(1F)));
        using var fill = new SolidBrush(color);
        graphics.DrawRectangle(pen, batteryRect);
        graphics.FillRectangle(fill, batteryRect.Right + Scale(1), batteryRect.Top + Scale(2), Scale(2), Math.Max(1, batteryRect.Height - Scale(4)));
        var fillWidth = Math.Max(1, (batteryRect.Width - Scale(2)) * percent / 100);
        graphics.FillRectangle(fill, batteryRect.Left + Scale(1), batteryRect.Top + Scale(1), fillWidth, Math.Max(1, batteryRect.Height - Scale(2)));
        if (ShowsExternalPowerIndicator(snapshot))
        {
            DrawExternalPowerBolt(graphics, batteryRect);
        }
        var labelLeft = batteryRect.Right + Scale(15);
        var labelRect = new Rectangle(labelLeft, area.Top, Math.Max(0, area.Right - labelLeft), area.Height);
        TextRenderer.DrawText(graphics, label, _smallFont, labelRect, color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }

    private void DrawExternalPowerBolt(Graphics graphics, Rectangle batteryRect)
    {
        var centerX = batteryRect.Right + ScaleValue(7F);
        var centerY = batteryRect.Top + batteryRect.Height / 2F;
        var halfWidth = Math.Max(2.5F, ScaleValue(2.8F));
        var top = centerY - Math.Max(5F, ScaleValue(5F));
        var bottom = centerY + Math.Max(5F, ScaleValue(5F));
        var waist = Math.Max(0.9F, ScaleValue(1F));
        var points = new[]
        {
            new PointF(centerX + waist, top),
            new PointF(centerX - halfWidth, centerY + ScaleValue(0.25F)),
            new PointF(centerX - ScaleValue(0.15F), centerY + ScaleValue(0.25F)),
            new PointF(centerX - waist, bottom),
            new PointF(centerX + halfWidth, centerY - ScaleValue(0.25F)),
            new PointF(centerX + ScaleValue(0.15F), centerY - ScaleValue(0.25F))
        };
        using var bolt = new SolidBrush(Color.FromArgb(103, 238, 142));
        graphics.FillPolygon(bolt, points);
    }

    private void DrawPowerMode(Graphics graphics, Rectangle area, PowerModeKind mode, string label)
    {
        var color = mode switch
        {
            PowerModeKind.Saver => Color.FromArgb(247, 190, 80),
            PowerModeKind.Performance => Color.FromArgb(104, 202, 255),
            PowerModeKind.Balanced => Color.FromArgb(214, 222, 231),
            _ => Color.FromArgb(170, 180, 191)
        };
        TextRenderer.DrawText(graphics, label, _smallFont, area, color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }

    internal static string PowerSourceLabel(SystemSnapshot snapshot) => snapshot.OnAcPower
        ? snapshot.Charging
            ? $"Charging {snapshot.BatteryPercent}%"
            : $"Plugged in {snapshot.BatteryPercent}%"
        : $"Battery {snapshot.BatteryPercent}%";

    internal static bool ShowsExternalPowerIndicator(SystemSnapshot snapshot) => snapshot.OnAcPower;

    internal static string PowerModeLabel(PowerModeKind mode) => mode switch
    {
        PowerModeKind.Saver => "Power saver",
        PowerModeKind.Balanced => "Balanced",
        PowerModeKind.Performance => "High performance",
        _ => "Power mode"
    };

    private static SystemSnapshot ApplyPowerPreview(SystemSnapshot snapshot, string? preview) =>
        preview?.ToLowerInvariant() switch
        {
            "battery-saver" => snapshot with
            {
                BatteryPercent = 31,
                OnAcPower = false,
                Charging = false,
                PowerMode = PowerModeKind.Saver
            },
            "battery-balanced" => snapshot with
            {
                BatteryPercent = 68,
                OnAcPower = false,
                Charging = false,
                PowerMode = PowerModeKind.Balanced
            },
            "charging-performance" => snapshot with
            {
                BatteryPercent = 74,
                OnAcPower = true,
                Charging = true,
                PowerMode = PowerModeKind.Performance
            },
            _ => snapshot
        };

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
        var trayHit = _trayHits.FirstOrDefault(hit => hit.Bounds.Contains(e.Location));
        if (trayHit.App is not null)
        {
            if (_hoveredTrayKey == trayHit.App.Key) return;
            _hovered = null;
            _hoveredTrayKey = trayHit.App.Key;
            Cursor = Cursors.Hand;
            _toolTip.SetToolTip(this, trayHit.App.Name);
            Invalidate();
            return;
        }
        var hovered = _hits.FirstOrDefault(hit => hit.Bounds.Contains(e.Location)).Action;
        BarAction? next = _hits.Any(hit => hit.Bounds.Contains(e.Location)) ? hovered : null;
        if (_hovered == next && _hoveredTrayKey is null) return;
        _hovered = next;
        _hoveredTrayKey = null;
        _toolTip.SetToolTip(this, string.Empty);
        Cursor = next is null ? Cursors.Default : Cursors.Hand;
        Invalidate();
    }

    private void OnMouseUp(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        if (IsShowDesktopCorner(e.Location, ClientSize, Scale(LogicalCornerHitSize)))
        {
            AppLog.Write($"Show Desktop corner clicked on {_screen.DeviceName}: x={e.X} width={Width}");
            MenuRouter.Send("desktop");
            return;
        }

        var trayHit = _trayHits.FirstOrDefault(item => item.Bounds.Contains(e.Location));
        if (trayHit.App is not null)
        {
            try { TrayAppLauncher.Activate(trayHit.App); }
            catch (Exception ex) { AppLog.Write($"Tray app activation failed for {trayHit.App.Name}: {ex.Message}"); }
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
            case BarAction.TrayOverflow:
                ShowTrayOverflow(PointToScreen(new Point(e.X, Height)));
                break;
            case BarAction.Notifications:
            case BarAction.Calendar:
                MenuRouter.OpenNotifications();
                break;
        }
    }

    private void ShowTrayOverflow(Point screenLocation)
    {
        var apps = _state.Snapshot.TrayApps.Skip(3).ToArray();
        if (apps.Length == 0) return;
        var menu = new ContextMenuStrip
        {
            ShowImageMargin = true,
            BackColor = Color.FromArgb(32, 36, 43),
            ForeColor = Color.FromArgb(241, 246, 251),
            Renderer = new ToolStripProfessionalRenderer(new TrayMenuColorTable())
        };
        foreach (var app in apps)
        {
            var item = new ToolStripMenuItem(app.Name) { ForeColor = menu.ForeColor };
            var image = _trayIcons.Get(app);
            if (image is not null) item.Image = new Bitmap(image, new Size(16, 16));
            item.Click += (_, _) =>
            {
                try { TrayAppLauncher.Activate(app); }
                catch (Exception ex) { AppLog.Write($"Tray overflow activation failed for {app.Name}: {ex.Message}"); }
            };
            menu.Items.Add(item);
        }
        menu.Closed += (_, _) => menu.Dispose();
        menu.Show(screenLocation);
    }

    internal static bool IsShowDesktopCorner(Point location, Size clientSize, int hitSize) =>
        location.Y >= 0 && location.Y < hitSize &&
        (location.X >= 0 && location.X < hitSize ||
         location.X >= clientSize.Width - hitSize && location.X < clientSize.Width);

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

    private async Task ReassertAppBarAfterStartupAsync()
    {
        foreach (var delay in new[] { 1000, 4000 })
        {
            await Task.Delay(delay);
            if (IsDisposed || !IsHandleCreated || !_appBarRegistered) return;
            PositionAppBar();
            EnsureTopmost();
            AppLog.Write($"Reasserted appbar {_screen.DeviceName} bounds={Bounds}");
        }
    }

    private float DpiScale => Math.Max(1F, DeviceDpi / 96F);
    private float VisualScale => Math.Max(DpiScale, _screen.Primary ? 1F : 1.5F);
    private int Scale(int logical) => Math.Max(1, (int)Math.Round(logical * VisualScale));
    private float ScaleValue(float logical) => Math.Max(1F, logical * VisualScale);

    private void ConfigureTypography()
    {
        _typography?.Dispose();
        var opticalScale = 1F + ((VisualScale / DpiScale) - 1F) * 0.3F;
        _typography = new Typography(opticalScale);
        _textFont = _typography.Text;
        _semiboldFont = _typography.Emphasis;
        _smallFont = _typography.Telemetry;
        _iconFont = _typography.Icon;
        AppLog.Write($"Typography {_screen.DeviceName} text={_textFont.Name}; emphasis={_semiboldFont.Name}; telemetry={_smallFont.Name}; dpi={DeviceDpi}; visualScale={VisualScale:0.##}");
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _state.Changed -= OnStateChanged;
            _appleMark?.Dispose();
            _trayIcons.Dispose();
            _toolTip.Dispose();
            _typography?.Dispose();
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
