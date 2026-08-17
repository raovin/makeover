using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.IO.Pipes;
using System.Globalization;
using System.Text;
using System.Xml.Linq;

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

internal enum TelemetryKind
{
    Cpu,
    Memory,
    Network,
    Codex,
    Claude,
    Grok,
    Gemini
}

internal sealed record TelemetrySegment(TelemetryKind Kind, string Text);

internal static class OpenAiBlossomAsset
{
    internal static GraphicsPath? TryLoad(string path)
    {
        if (!File.Exists(path)) return null;
        try
        {
            var document = XDocument.Load(path, LoadOptions.PreserveWhitespace);
            var pathData = document.Root?
                .Descendants()
                .Where(element => element.Name.LocalName.Equals("path", StringComparison.Ordinal))
                .Select(element => new
                {
                    Fill = element.Attribute("fill")?.Value,
                    Data = element.Attribute("d")?.Value
                })
                .FirstOrDefault(candidate =>
                    candidate.Fill?.Equals("black", StringComparison.OrdinalIgnoreCase) == true &&
                    !string.IsNullOrWhiteSpace(candidate.Data))?
                .Data;
            return string.IsNullOrWhiteSpace(pathData) ? null : SvgPathParser.TryParse(pathData);
        }
        catch
        {
            return null;
        }
    }
}

internal static class SvgPathParser
{
    private static readonly System.Text.RegularExpressions.Regex TokenPattern =
        new(@"[A-Za-z]|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?",
            System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    internal static GraphicsPath? TryParse(string data)
    {
        try
        {
            var tokens = OpenAiBlossomAssetTokenize(data);
            var path = new GraphicsPath { FillMode = FillMode.Winding };
            var index = 0;
            var command = '\0';
            var current = PointF.Empty;
            var figureStart = PointF.Empty;
            while (index < tokens.Count)
            {
                if (IsCommand(tokens[index])) command = tokens[index++][0];
                if (command == '\0') return DisposeAndReturnNull(path);

                var normalized = char.ToUpperInvariant(command);
                var relative = char.IsLower(command);
                switch (normalized)
                {
                    case 'M':
                        if (!TryReadPair(tokens, ref index, out var move)) return DisposeAndReturnNull(path);
                        current = relative ? Add(current, move) : move;
                        path.StartFigure();
                        path.AddLine(current, current);
                        figureStart = current;
                        command = relative ? 'l' : 'L';
                        break;
                    case 'L':
                        if (!TryReadPair(tokens, ref index, out var line)) return DisposeAndReturnNull(path);
                        var lineEnd = relative ? Add(current, line) : line;
                        path.AddLine(current, lineEnd);
                        current = lineEnd;
                        break;
                    case 'H':
                        if (!TryReadNumber(tokens, ref index, out var horizontal)) return DisposeAndReturnNull(path);
                        var horizontalEnd = new PointF(
                            (float)(relative ? current.X + horizontal : horizontal),
                            current.Y);
                        path.AddLine(current, horizontalEnd);
                        current = horizontalEnd;
                        break;
                    case 'V':
                        if (!TryReadNumber(tokens, ref index, out var vertical)) return DisposeAndReturnNull(path);
                        var verticalEnd = new PointF(
                            current.X,
                            (float)(relative ? current.Y + vertical : vertical));
                        path.AddLine(current, verticalEnd);
                        current = verticalEnd;
                        break;
                    case 'C':
                        if (!TryReadPair(tokens, ref index, out var controlOne) ||
                            !TryReadPair(tokens, ref index, out var controlTwo) ||
                            !TryReadPair(tokens, ref index, out var cubicEnd))
                        {
                            return DisposeAndReturnNull(path);
                        }
                        if (relative)
                        {
                            controlOne = Add(current, controlOne);
                            controlTwo = Add(current, controlTwo);
                            cubicEnd = Add(current, cubicEnd);
                        }
                        path.AddBezier(current, controlOne, controlTwo, cubicEnd);
                        current = cubicEnd;
                        break;
                    case 'Z':
                        path.CloseFigure();
                        current = figureStart;
                        command = '\0';
                        break;
                    default:
                        return DisposeAndReturnNull(path);
                }
            }

            return path.PointCount == 0 ? DisposeAndReturnNull(path) : path;
        }
        catch
        {
            return null;
        }
    }

    private static List<string> OpenAiBlossomAssetTokenize(string data) =>
        TokenPattern.Matches(data).Select(match => match.Value).ToList();

    private static bool IsCommand(string token) =>
        token.Length == 1 && char.IsLetter(token[0]);

    private static bool TryReadPair(
        IReadOnlyList<string> tokens,
        ref int index,
        out PointF point)
    {
        point = default;
        if (!TryReadNumber(tokens, ref index, out var x) ||
            !TryReadNumber(tokens, ref index, out var y))
        {
            return false;
        }

        point = new PointF((float)x, (float)y);
        return true;
    }

    private static bool TryReadNumber(
        IReadOnlyList<string> tokens,
        ref int index,
        out double value)
    {
        if (index >= tokens.Count ||
            IsCommand(tokens[index]) ||
            !double.TryParse(tokens[index], NumberStyles.Float, CultureInfo.InvariantCulture, out value))
        {
            value = 0;
            return false;
        }

        index++;
        return true;
    }

    private static PointF Add(PointF left, PointF right) =>
        new(left.X + right.X, left.Y + right.Y);

    private static GraphicsPath? DisposeAndReturnNull(GraphicsPath path)
    {
        path.Dispose();
        return null;
    }
}

internal sealed class MenuBarForm : Form
{
    internal const int LogicalHeight = 28;
    internal const int LogicalCornerHitSize = 8;
    internal const int LogicalProviderIconSize = 12;
    private const int LogicalTelemetryIconSize = 11;
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
    private Image? _claudeMark;
    private Image? _grokMark;
    private GraphicsPath? _openAiBlossom;
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
        if (preview) Text = "MacMakeover Menu Bar Preview";
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

        var openAiAsset = Path.Combine(AppContext.BaseDirectory, "Assets", "OpenAI-Blossom.svg");
        _openAiBlossom = OpenAiBlossomAsset.TryLoad(openAiAsset);
        _claudeMark = TryLoadProviderMark(
            Path.Combine(AppContext.BaseDirectory, "Assets", "Claude-Mark-32.png"));
        _grokMark = TryLoadProviderMark(
            Path.Combine(AppContext.BaseDirectory, "Assets", "Grok-Mark-144.png"));

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
            // Explorer recreated the taskbar. Clear registration only via ABM_REMOVE
            // when we still believe we own one, then re-register.
            if (_appBarRegistered) RemoveAppBar();
            RegisterAppBar();
        }
        if (_appBarCallback != 0 && message.Msg == _appBarCallback && message.WParam.ToInt32() == NativeMethods.AbnPosChanged)
        {
            PositionAppBar();
        }
        base.WndProc(ref message);
    }

    /// <summary>
    /// Pure ABM_NEW acceptance: shell returns nonzero only when registration succeeded.
    /// </summary>
    internal static bool IsAppBarRegistrationAccepted(UIntPtr result) => result != UIntPtr.Zero;

    /// <summary>
    /// Pure startup-reassert follow-up after optional ABM_NEW retry. Avoids a second
    /// PositionAppBar when RegisterAppBar already positioned a newly registered bar.
    /// </summary>
    internal enum StartupReassertFollowUp
    {
        /// <summary>Already registered before this iteration — one reassert PositionAppBar.</summary>
        PositionAppBar,
        /// <summary>RegisterAppBar just succeeded and already positioned once.</summary>
        None,
        /// <summary>Still unregistered — DPI-correct visible bounds only; never ABM_SETPOS.</summary>
        ApplyVisibleBoundsOnly
    }

    /// <summary>
    /// Decides the single follow-up action for one startup reassert iteration.
    /// </summary>
    internal static StartupReassertFollowUp DecideStartupReassertFollowUp(
        bool wasRegistered,
        bool isRegistered)
    {
        if (!isRegistered) return StartupReassertFollowUp.ApplyVisibleBoundsOnly;
        if (wasRegistered) return StartupReassertFollowUp.PositionAppBar;
        return StartupReassertFollowUp.None;
    }

    /// <summary>
    /// Top-edge bar rectangle for a screen. Shared by reserved positioning and the
    /// unregistered visible-only fallback (no AppBar messages involved).
    /// </summary>
    internal static Rectangle ComputeTopBarBounds(Rectangle screenBounds, int scaledHeight) =>
        new(screenBounds.Left, screenBounds.Top, screenBounds.Width, Math.Max(1, scaledHeight));

    internal static int ComputeAppBarReservationHeight(int visibleHeight) =>
        Math.Max(1, visibleHeight) + 1;

    internal static Rectangle ComputeVisibleBounds(
        Rectangle reservedBounds,
        int visibleHeight) =>
        new(
            reservedBounds.Left,
            reservedBounds.Top,
            reservedBounds.Width,
            Math.Max(1, visibleHeight));

    private void RegisterAppBar()
    {
        if (_appBarRegistered) return;
        if (IsDisposed || !IsHandleCreated) return;
        _appBarCallback = NativeMethods.RegisterWindowMessage($"MacMakeover.MenuBar.{Handle}");
        var data = CreateAppBarData();
        data.CallbackMessage = _appBarCallback;
        var result = NativeMethods.SHAppBarMessage(NativeMethods.AbmNew, ref data);
        if (!IsAppBarRegistrationAccepted(result))
        {
            AppLog.Write(
                $"AppBar registration failed {_screen.DeviceName} handle={Handle} dpi={DeviceDpi}");
            // Keep the form visually DPI-correct even without a work-area reservation.
            ApplyVisibleTopBarBounds();
            return;
        }
        _appBarRegistered = true;
        PositionAppBar();
        AppLog.Write($"Registered appbar {_screen.DeviceName} bounds={Bounds} dpi={DeviceDpi}");
    }

    private void PositionAppBar()
    {
        if (!_appBarRegistered || IsDisposed) return;
        var visibleHeight = Scale(LogicalHeight);
        var reservationHeight = ComputeAppBarReservationHeight(visibleHeight);
        var desired = ComputeTopBarBounds(_screen.Bounds, reservationHeight);
        var data = CreateAppBarData();
        data.Edge = NativeMethods.AbeTop;
        data.Bounds = new NativeMethods.Rect
        {
            Left = desired.Left,
            Top = desired.Top,
            Right = desired.Right,
            Bottom = desired.Bottom
        };
        NativeMethods.SHAppBarMessage(NativeMethods.AbmQueryPos, ref data);
        data.Bounds.Top = _screen.Bounds.Top;
        data.Bounds.Bottom = data.Bounds.Top + reservationHeight;
        NativeMethods.SHAppBarMessage(NativeMethods.AbmSetPos, ref data);
        var reservedBounds = data.Bounds.ToRectangle();
        ApplyNativeBounds(ComputeVisibleBounds(reservedBounds, visibleHeight));
    }

    /// <summary>
    /// Unregistered bars only: set DPI-correct visible form bounds without ABM_SETPOS.
    /// Safe when reservation cannot be established; does not claim shell work area.
    /// </summary>
    private void ApplyVisibleTopBarBounds()
    {
        if (_appBarRegistered || IsDisposed || !IsHandleCreated) return;
        ApplyNativeBounds(ComputeTopBarBounds(_screen.Bounds, Scale(LogicalHeight)));
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

    internal void ReleaseAppBarForDisplayRebuild()
    {
        // Release while the HWND is still valid; Close may destroy the handle before
        // Dispose runs, so relying only on OnHandleDestroyed is not deterministic.
        if (IsHandleCreated) RemoveAppBar();
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
        foreach (var app in snapshot.TrayApps)
        {
            x = DrawTrayItem(graphics, x, app);
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
        if (available <= 0) return;

        var candidates = new[]
        {
            new[]
            {
                new TelemetrySegment(TelemetryKind.Cpu, $"{snapshot.CpuPercent}%"),
                new TelemetrySegment(TelemetryKind.Memory, $"{snapshot.UsedMemoryGb:0}/{snapshot.TotalMemoryGb:0} GB"),
                new TelemetrySegment(TelemetryKind.Network, $"\u2193{FormatRate(snapshot.DownloadBytesPerSecond)} \u2191{FormatRate(snapshot.UploadBytesPerSecond)}"),
                new TelemetrySegment(TelemetryKind.Codex, snapshot.AiUsage.Codex.RenderedText),
                new TelemetrySegment(TelemetryKind.Claude, snapshot.AiUsage.Claude.RenderedText),
                new TelemetrySegment(TelemetryKind.Grok, snapshot.AiUsage.Grok.RenderedText),
                new TelemetrySegment(TelemetryKind.Gemini, snapshot.AiUsage.Gemini.RenderedText)
            },
            new[]
            {
                new TelemetrySegment(TelemetryKind.Cpu, $"{snapshot.CpuPercent}%"),
                new TelemetrySegment(TelemetryKind.Memory, $"{snapshot.UsedMemoryGb:0}/{snapshot.TotalMemoryGb:0} GB"),
                new TelemetrySegment(TelemetryKind.Codex, snapshot.AiUsage.Codex.RenderedText),
                new TelemetrySegment(TelemetryKind.Claude, snapshot.AiUsage.Claude.RenderedText),
                new TelemetrySegment(TelemetryKind.Grok, snapshot.AiUsage.Grok.RenderedText),
                new TelemetrySegment(TelemetryKind.Gemini, snapshot.AiUsage.Gemini.RenderedText)
            },
            new[]
            {
                new TelemetrySegment(TelemetryKind.Cpu, $"{snapshot.CpuPercent}%"),
                new TelemetrySegment(TelemetryKind.Memory, $"{snapshot.UsedMemoryGb:0}G"),
                new TelemetrySegment(TelemetryKind.Codex, snapshot.AiUsage.Codex.RenderedText),
                new TelemetrySegment(TelemetryKind.Claude, snapshot.AiUsage.Claude.RenderedText),
                new TelemetrySegment(TelemetryKind.Grok, snapshot.AiUsage.Grok.RenderedText),
                new TelemetrySegment(TelemetryKind.Gemini, snapshot.AiUsage.Gemini.RenderedText)
            },
            new[]
            {
                new TelemetrySegment(TelemetryKind.Cpu, $"{snapshot.CpuPercent}%"),
                new TelemetrySegment(TelemetryKind.Codex, snapshot.AiUsage.Codex.RenderedText),
                new TelemetrySegment(TelemetryKind.Claude, snapshot.AiUsage.Claude.RenderedText),
                new TelemetrySegment(TelemetryKind.Grok, snapshot.AiUsage.Grok.RenderedText),
                new TelemetrySegment(TelemetryKind.Gemini, snapshot.AiUsage.Gemini.RenderedText)
            },
            new[]
            {
                new TelemetrySegment(TelemetryKind.Codex, snapshot.AiUsage.Codex.RenderedText),
                new TelemetrySegment(TelemetryKind.Claude, snapshot.AiUsage.Claude.RenderedText),
                new TelemetrySegment(TelemetryKind.Grok, snapshot.AiUsage.Grok.RenderedText),
                new TelemetrySegment(TelemetryKind.Gemini, snapshot.AiUsage.Gemini.RenderedText)
            }
        };
        var battery = PowerSourceLabel(snapshot);
        var powerMode = PowerModeLabel(snapshot.PowerMode);
        // Keep a permanent slot between the battery and its label so AC status never
        // shifts the rest of the centered telemetry group when power is connected.
        var batteryWidth = TextRenderer.MeasureText(battery, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(34);
        var powerModeWidth = TextRenderer.MeasureText(powerMode, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width + Scale(6);
        TelemetrySegment[]? segments = null;
        var groupWidth = 0;
        var candidateWidths = candidates
            .Select(candidate => candidate.Sum(MeasureTelemetry) +
                                 Math.Max(0, candidate.Length) * Scale(17) + batteryWidth +
                                 Scale(17) + powerModeWidth)
            .ToArray();
        var selectedCandidate = SelectTelemetryCandidateIndex(candidateWidths, available);
        if (selectedCandidate >= 0)
        {
            segments = candidates[selectedCandidate];
            groupWidth = candidateWidths[selectedCandidate];
        }
        if (segments is null) return;

        var minimumX = leftEnd + Scale(8);
        var maximumX = rightStart - groupWidth - Scale(8);
        if (maximumX < minimumX) return;
        var x = CalculateTelemetryX(Width, groupWidth, leftEnd, rightStart, Scale(8));
        foreach (var segment in segments)
        {
            var width = MeasureTelemetry(segment);
            DrawTelemetry(graphics, segment, new Rectangle(x, 0, width, Height));
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

    internal static int SelectTelemetryCandidateIndex(
        IReadOnlyList<int> candidateWidths,
        int availableWidth)
    {
        for (var index = 0; index < candidateWidths.Count; index++)
        {
            if (candidateWidths[index] <= availableWidth) return index;
        }

        return -1;
    }

    internal static int CalculateTelemetryX(int width, int groupWidth, int leftEnd, int rightStart, int inset)
    {
        var minimumX = leftEnd + inset;
        var maximumX = rightStart - groupWidth - inset;
        if (maximumX < minimumX) return minimumX;
        var screenCenteredX = (width - groupWidth) / 2;
        var availableSpaceCenteredX = leftEnd + (rightStart - leftEnd - groupWidth) / 2;
        // Keep the familiar centered composition, but lean toward the free space so
        // the denser right-side controls have more breathing room.
        return Math.Clamp((screenCenteredX * 2 + availableSpaceCenteredX) / 3, minimumX, maximumX);
    }

    private int MeasureTelemetry(TelemetrySegment segment) =>
        Scale(TelemetryIconSize(segment.Kind)) +
        Scale(3) +
        TextRenderer.MeasureText(segment.Text, _smallFont, Size.Empty, TextFormatFlags.NoPadding).Width;

    private static int TelemetryIconSize(TelemetryKind kind) =>
        kind is TelemetryKind.Codex or TelemetryKind.Claude or TelemetryKind.Grok or TelemetryKind.Gemini
            ? LogicalProviderIconSize
            : LogicalTelemetryIconSize;

    private void DrawTelemetry(Graphics graphics, TelemetrySegment segment, Rectangle area)
    {
        var color = Color.FromArgb(228, 233, 239);
        var iconSize = TelemetryIconSize(segment.Kind);
        var icon = new Rectangle(
            area.Left,
            area.Top + (area.Height - Scale(iconSize)) / 2,
            Scale(iconSize),
            Scale(iconSize));
        using var pen = new Pen(color, Math.Max(1F, ScaleValue(1F)))
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round,
            LineJoin = LineJoin.Round
        };

        switch (segment.Kind)
        {
            case TelemetryKind.Cpu:
                var chip = Rectangle.Inflate(icon, -Scale(2), -Scale(2));
                graphics.DrawRectangle(pen, chip);
                for (var offset = Scale(2); offset <= Scale(8); offset += Scale(3))
                {
                    graphics.DrawLine(pen, icon.Left + offset, icon.Top, icon.Left + offset, chip.Top);
                    graphics.DrawLine(pen, icon.Left + offset, chip.Bottom, icon.Left + offset, icon.Bottom);
                    graphics.DrawLine(pen, icon.Left, icon.Top + offset, chip.Left, icon.Top + offset);
                    graphics.DrawLine(pen, chip.Right, icon.Top + offset, icon.Right, icon.Top + offset);
                }
                break;
            case TelemetryKind.Memory:
                var memory = new Rectangle(icon.Left, icon.Top + Scale(2), icon.Width, Scale(7));
                graphics.DrawRectangle(pen, memory);
                graphics.DrawLine(pen, memory.Left + Scale(2), memory.Bottom, memory.Left + Scale(2), icon.Bottom);
                graphics.DrawLine(pen, memory.Right - Scale(2), memory.Bottom, memory.Right - Scale(2), icon.Bottom);
                for (var offset = Scale(2); offset <= Scale(8); offset += Scale(3))
                {
                    graphics.DrawLine(pen, icon.Left + offset, memory.Top + Scale(2), icon.Left + offset, memory.Bottom - Scale(2));
                }
                break;
            case TelemetryKind.Network:
                graphics.DrawLine(pen, icon.Left + Scale(3), icon.Bottom, icon.Left + Scale(3), icon.Top + Scale(1));
                graphics.DrawLine(pen, icon.Left + Scale(1), icon.Top + Scale(3), icon.Left + Scale(3), icon.Top + Scale(1));
                graphics.DrawLine(pen, icon.Left + Scale(5), icon.Top + Scale(3), icon.Left + Scale(3), icon.Top + Scale(1));
                graphics.DrawLine(pen, icon.Right - Scale(3), icon.Top, icon.Right - Scale(3), icon.Bottom - Scale(1));
                graphics.DrawLine(pen, icon.Right - Scale(5), icon.Bottom - Scale(3), icon.Right - Scale(3), icon.Bottom - Scale(1));
                graphics.DrawLine(pen, icon.Right - Scale(1), icon.Bottom - Scale(3), icon.Right - Scale(3), icon.Bottom - Scale(1));
                break;
            case TelemetryKind.Codex:
                DrawOpenAiMark(graphics, icon, color);
                break;
            case TelemetryKind.Claude:
                DrawProviderRasterMark(graphics, icon, _claudeMark);
                break;
            case TelemetryKind.Grok:
                DrawProviderRasterMark(graphics, icon, _grokMark);
                break;
            case TelemetryKind.Gemini:
                DrawAntigravityMark(graphics, icon);
                break;
        }

        var textRect = new Rectangle(icon.Right + Scale(3), area.Top, area.Right - icon.Right - Scale(3), area.Height);
        TextRenderer.DrawText(graphics, segment.Text, _smallFont, textRect, color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
            TextFormatFlags.NoPadding);
    }

    private void DrawOpenAiMark(Graphics graphics, Rectangle icon, Color color)
    {
        if (_openAiBlossom is null) return;

        using var mark = (GraphicsPath)_openAiBlossom.Clone();
        var sourceBounds = mark.GetBounds();
        var scale = Math.Min(icon.Width / sourceBounds.Width, icon.Height / sourceBounds.Height);
        var targetLeft = icon.Left + (icon.Width - sourceBounds.Width * scale) / 2F;
        var targetTop = icon.Top + (icon.Height - sourceBounds.Height * scale) / 2F;
        using var transform = new Matrix(
            scale,
            0F,
            0F,
            scale,
            targetLeft - sourceBounds.Left * scale,
            targetTop - sourceBounds.Top * scale);
        mark.Transform(transform);
        using var brush = new SolidBrush(color);
        graphics.FillPath(brush, mark);
    }

    internal static Bitmap? TryLoadProviderMark(string path)
    {
        if (!File.Exists(path)) return null;
        try
        {
            using var source = Image.FromFile(path);
            return new Bitmap(source);
        }
        catch
        {
            return null;
        }
    }

    internal static void DrawProviderRasterMark(Graphics graphics, Rectangle icon, Image? mark)
    {
        if (mark is null) return;

        // Claude's 32 px favicon is already pixel-optimized; Grok is rasterized once
        // from its official vector. Keep the runtime path to one integer-aligned scale
        // step so neither mark inherits the blur of hand-drawn subpixel strokes.
        // The official assets carry their own optical whitespace. Using the full
        // integer-aligned icon box preserves Claude's ray separation at 150% DPI;
        // shrinking it to 14 physical pixels visibly merges the smallest rays.
        var destination = icon;
        var previousInterpolation = graphics.InterpolationMode;
        var previousPixelOffset = graphics.PixelOffsetMode;
        var previousCompositingQuality = graphics.CompositingQuality;
        try
        {
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.CompositingQuality = CompositingQuality.GammaCorrected;
            using var attributes = new System.Drawing.Imaging.ImageAttributes();
            attributes.SetWrapMode(WrapMode.TileFlipXY);
            graphics.DrawImage(
                mark,
                destination,
                0,
                0,
                mark.Width,
                mark.Height,
                GraphicsUnit.Pixel,
                attributes);
        }
        finally
        {
            graphics.InterpolationMode = previousInterpolation;
            graphics.PixelOffsetMode = previousPixelOffset;
            graphics.CompositingQuality = previousCompositingQuality;
        }
    }

    internal static void DrawAntigravityMark(Graphics graphics, Rectangle icon)
    {
        // Antigravity's rounded arch is the product mark used by the AGY client. The
        // deep inner cutout and outward feet preserve the silhouette at menu-bar scale.
        using var path = new GraphicsPath();
        path.StartFigure();
        path.AddBezier(
            IconPoint(icon, 0.20F, 11.15F),
            IconPoint(icon, 1.15F, 11.45F),
            IconPoint(icon, 2.25F, 10.15F),
            IconPoint(icon, 3.00F, 8.55F));
        path.AddBezier(
            IconPoint(icon, 3.00F, 8.55F),
            IconPoint(icon, 3.70F, 7.05F),
            IconPoint(icon, 4.15F, 3.50F),
            IconPoint(icon, 4.80F, 1.55F));
        path.AddBezier(
            IconPoint(icon, 4.80F, 1.55F),
            IconPoint(icon, 5.10F, 0.55F),
            IconPoint(icon, 5.45F, 0.25F),
            IconPoint(icon, 6.00F, 0.25F));
        path.AddBezier(
            IconPoint(icon, 6.00F, 0.25F),
            IconPoint(icon, 6.55F, 0.25F),
            IconPoint(icon, 6.90F, 0.55F),
            IconPoint(icon, 7.20F, 1.55F));
        path.AddBezier(
            IconPoint(icon, 7.20F, 1.55F),
            IconPoint(icon, 7.85F, 3.50F),
            IconPoint(icon, 8.30F, 7.05F),
            IconPoint(icon, 9.00F, 8.55F));
        path.AddBezier(
            IconPoint(icon, 9.00F, 8.55F),
            IconPoint(icon, 9.75F, 10.15F),
            IconPoint(icon, 10.85F, 11.45F),
            IconPoint(icon, 11.80F, 11.15F));
        path.AddBezier(
            IconPoint(icon, 11.80F, 11.15F),
            IconPoint(icon, 10.75F, 10.45F),
            IconPoint(icon, 9.85F, 9.15F),
            IconPoint(icon, 9.10F, 7.90F));
        path.AddBezier(
            IconPoint(icon, 9.10F, 7.90F),
            IconPoint(icon, 8.05F, 6.15F),
            IconPoint(icon, 7.30F, 5.35F),
            IconPoint(icon, 6.00F, 5.35F));
        path.AddBezier(
            IconPoint(icon, 6.00F, 5.35F),
            IconPoint(icon, 4.70F, 5.35F),
            IconPoint(icon, 3.95F, 6.15F),
            IconPoint(icon, 2.90F, 7.90F));
        path.AddBezier(
            IconPoint(icon, 2.90F, 7.90F),
            IconPoint(icon, 2.15F, 9.15F),
            IconPoint(icon, 1.25F, 10.45F),
            IconPoint(icon, 0.20F, 11.15F));
        path.CloseFigure();

        using var gradient = new LinearGradientBrush(
            icon,
            Color.FromArgb(255, 194, 40),
            Color.FromArgb(47, 125, 255),
            90F)
        {
            InterpolationColors = new ColorBlend
            {
                Colors = [
                    Color.FromArgb(255, 190, 35),
                    Color.FromArgb(244, 102, 69),
                    Color.FromArgb(77, 183, 132),
                    Color.FromArgb(47, 125, 255)
                ],
                Positions = [0F, 0.23F, 0.48F, 1F]
            }
        };
        graphics.FillPath(gradient, path);
    }

    private static PointF IconPoint(Rectangle icon, float x, float y) =>
        new(icon.Left + icon.Width * x / 12F, icon.Top + icon.Height * y / 12F);

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

    internal static string PowerSourceLabel(SystemSnapshot snapshot) => $"{snapshot.BatteryPercent}%";

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

    private static string FormatRate(long bytesPerSecond) =>
        SystemStateProvider.FormatNetworkRate(bytesPerSecond);

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
            case BarAction.Notifications:
            case BarAction.Calendar:
                MenuRouter.OpenNotifications();
                break;
        }
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
        // Bounded startup reassert only (1s and 4s). Unregistered bars retry ABM_NEW here;
        // do not add a resident recovery timer or Dock-style retry loop.
        foreach (var delay in new[] { 1000, 4000 })
        {
            await Task.Delay(delay);
            if (IsDisposed || !IsHandleCreated) return;

            var wasRegistered = _appBarRegistered;
            if (!wasRegistered)
            {
                RegisterAppBar();
                if (!_appBarRegistered)
                {
                    AppLog.Write(
                        $"Startup reassert could not register appbar {_screen.DeviceName} handle={Handle} dpi={DeviceDpi}");
                }
            }

            // Exactly one position path per iteration:
            // - already registered → one reassert PositionAppBar
            // - newly registered → RegisterAppBar already positioned once (None)
            // - still unregistered → visible DPI bounds only, never ABM_SETPOS
            switch (DecideStartupReassertFollowUp(wasRegistered, _appBarRegistered))
            {
                case StartupReassertFollowUp.PositionAppBar:
                    PositionAppBar();
                    break;
                case StartupReassertFollowUp.ApplyVisibleBoundsOnly:
                    ApplyVisibleTopBarBounds();
                    break;
            }

            EnsureTopmost();
            AppLog.Write(
                _appBarRegistered
                    ? $"Reasserted appbar {_screen.DeviceName} bounds={Bounds}"
                    : $"Applied visible top-bar bounds without reservation {_screen.DeviceName} bounds={Bounds}");
        }
    }

    private float DpiScale => Math.Max(1F, DeviceDpi / 96F);
    private float VisualScale => Math.Max(DpiScale, _screen.Primary ? 1F : 1.5F);
    private int Scale(int logical) => ScaleLogical(logical, VisualScale);
    private float ScaleValue(float logical) => Math.Max(1F, logical * VisualScale);

    internal static int ScaleLogical(int logical, float scale) =>
        Math.Max(1, (int)Math.Round(logical * Math.Max(1F, scale)));

    internal static float ComputeTypographyOpticalScale(float visualScale, float dpiScale) =>
        1F + (Math.Max(1F, visualScale) / Math.Max(1F, dpiScale) - 1F) * 0.3F;

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
            _claudeMark?.Dispose();
            _grokMark?.Dispose();
            _openAiBlossom?.Dispose();
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
