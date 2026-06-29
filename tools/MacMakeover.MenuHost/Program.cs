using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.IO.Pipes;
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
            _current?.Close();
            _current?.Dispose();

            _current = command.Trim().ToLowerInvariant() switch
            {
                "apple" => MenuForm.CreateApple(),
                "control" => MenuForm.CreateControlCenter(),
                _ => null
            };

            if (_current is null) return;
            Program.Log($"Created {_current.Text} at {_current.Left},{_current.Top} size {_current.Width}x{_current.Height}");
            _current.FormClosed += (_, _) =>
            {
                _current = null;
            };
            _current.Show();
            NativeMethods.ShowAboveEverything(_current);
            _current.Activate();
            Program.Log($"Shown {_current.Text}, visible={_current.Visible}, handle={_current.Handle}");
        }
        catch (Exception ex)
        {
            Program.Log("ShowCommand failed: " + ex);
        }
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
    private readonly Color _panel = Color.FromArgb(33, 36, 45);
    private readonly Color _card = Color.FromArgb(48, 52, 65);
    private readonly Color _cardHover = Color.FromArgb(58, 64, 80);
    private readonly Color _hover = Color.FromArgb(44, 107, 237);
    private readonly Color _separator = Color.FromArgb(84, 91, 103);
    private readonly Color _primaryText = Color.FromArgb(246, 248, 251);
    private readonly Color _secondaryText = Color.FromArgb(174, 181, 191);
    private readonly List<MenuRow> _rows = [];
    private readonly System.Windows.Forms.Timer _outsideClickTimer;
    private readonly Font _regularFont;
    private readonly Font _boldFont;
    private readonly Font _smallFont;
    private readonly Font _smallBoldFont;
    private DateTime _shownAt;
    private bool _wasLeftMouseDown;
    private int _hoverIndex = -1;

    private MenuForm(int width)
    {
        AutoScaleMode = AutoScaleMode.Dpi;
        BackColor = _panel;
        _regularFont = new Font("Segoe UI", 9.7F, FontStyle.Regular, GraphicsUnit.Point);
        _boldFont = new Font("Segoe UI", 9.8F, FontStyle.Bold, GraphicsUnit.Point);
        _smallFont = new Font("Segoe UI", 8.3F, FontStyle.Regular, GraphicsUnit.Point);
        _smallBoldFont = new Font("Segoe UI", 8.6F, FontStyle.Bold, GraphicsUnit.Point);
        Font = _regularFont;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Width = width;
        Padding = new Padding(10);
        KeyPreview = true;
        DoubleBuffered = true;

        _outsideClickTimer = new System.Windows.Forms.Timer { Interval = 25 };
        _outsideClickTimer.Tick += (_, _) => CloseAfterOutsideClick();
        Shown += (_, _) =>
        {
            _shownAt = DateTime.UtcNow;
            _outsideClickTimer.Start();
        };
        FormClosed += (_, _) => _outsideClickTimer.Dispose();
        KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
        };
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        using var brush = new SolidBrush(_panel);
        e.Graphics.FillRectangle(brush, ClientRectangle);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(_panel);

        var y = Padding.Top;
        for (var i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            var rect = new Rectangle(Padding.Left, y, ClientSize.Width - Padding.Horizontal, row.Height);

            switch (row.Kind)
            {
                case MenuRowKind.Header:
                    DrawHeader(e.Graphics, rect, row);
                    break;
                case MenuRowKind.Card:
                    DrawCard(e.Graphics, rect, row, i == _hoverIndex);
                    break;
                case MenuRowKind.Separator:
                    using (var pen = new Pen(_separator))
                    {
                        var lineY = rect.Top + (rect.Height / 2);
                        e.Graphics.DrawLine(pen, rect.Left + 8, lineY, rect.Right - 8, lineY);
                    }
                    break;
                default:
                    DrawItem(e.Graphics, rect, row, i == _hoverIndex);
                    break;
            }

            y += row.Height;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var hit = HitTest(e.Location);
        if (hit == _hoverIndex) return;

        _hoverIndex = hit;
        Cursor = hit >= 0 && _rows[hit].Action is not null ? Cursors.Hand : Cursors.Default;
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

    public static MenuForm CreateApple()
    {
        var form = new MenuForm(352);
        form.Text = "Apple Menu";
        form.Location = new Point(8, 38);
        form.AddItem("About This Mac", () => Start("msinfo32.exe"));
        form.AddSeparator();
        form.AddItem("System Settings...", () => Start("ms-settings:"));
        form.AddItem("App Store", () => Start("ms-windows-store://home"));
        form.AddSeparator();
        form.AddItem("Recent Items", null, ">");
        form.AddSeparator();
        form.AddItem("Force Quit...", () => Start("taskmgr.exe"), "Ctrl+Shift+Esc");
        form.AddSeparator();
        form.AddItem("Sleep", () => Start("rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"));
        form.AddItem("Restart...", () => Confirm("Restart", "Restart this PC now?", "shutdown.exe", "/r /t 0"));
        form.AddItem("Shut Down...", () => Confirm("Shut Down", "Shut down this PC now?", "shutdown.exe", "/s /t 0"));
        form.AddSeparator();
        form.AddItem("Lock Screen", () => Start("rundll32.exe", "user32.dll,LockWorkStation"));
        form.AddItem($"Log Out {Environment.UserName}...", () => Confirm("Log Out", "Sign out now?", "shutdown.exe", "/l"));
        form.FitHeight();
        return form;
    }

    public static MenuForm CreateControlCenter()
    {
        var form = new MenuForm(348);
        form.Text = "Control Center";
        var screen = Screen.PrimaryScreen?.Bounds ?? new Rectangle(0, 0, 1280, 800);
        form.Location = new Point(screen.Right - form.Width - 8, 38);
        form.AddHeader("Control Center", GetBatterySummary());
        form.AddCard("Power & Battery Settings", "Open Windows power settings", () => Start("ms-settings:powersleep"));
        form.AddCard("System Settings", "Open Windows settings", () => Start("ms-settings:"));
        form.AddItem("Show Desktop", ToggleDesktop);
        form.AddItem("Lock Screen", () => Start("rundll32.exe", "user32.dll,LockWorkStation"));
        form.AddItem("Sleep", () => Start("rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"));
        form.AddItem("Restart...", () => Confirm("Restart", "Restart this PC now?", "shutdown.exe", "/r /t 0"));
        form.AddItem("Shut Down...", () => Confirm("Shut Down", "Shut down this PC now?", "shutdown.exe", "/s /t 0"));
        form.FitHeight();
        return form;
    }

    private void AddHeader(string title, string detail)
    {
        _rows.Add(new MenuRow(MenuRowKind.Header, title, detail, string.Empty, null, 48));
    }

    private void AddCard(string label, string detail, Action action)
    {
        _rows.Add(new MenuRow(MenuRowKind.Card, label, detail, string.Empty, action, 48));
    }

    private void AddItem(string label, Action? action, string shortcut = "")
    {
        _rows.Add(new MenuRow(MenuRowKind.Item, label, string.Empty, shortcut, action, 30));
    }

    private void AddSeparator()
    {
        _rows.Add(new MenuRow(MenuRowKind.Separator, string.Empty, string.Empty, string.Empty, null, 10));
    }

    private void FitHeight()
    {
        ClientSize = new Size(Width, _rows.Sum(row => row.Height) + Padding.Vertical);
    }

    private int HitTest(Point point)
    {
        var y = Padding.Top;
        for (var i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            var rect = new Rectangle(Padding.Left, y, ClientSize.Width - Padding.Horizontal, row.Height);
            if (rect.Contains(point)) return i;
            y += row.Height;
        }

        return -1;
    }

    private void DrawHeader(Graphics graphics, Rectangle rect, MenuRow row)
    {
        var titleRect = new Rectangle(rect.Left + 10, rect.Top + 4, rect.Width - 20, 22);
        var detailRect = new Rectangle(rect.Left + 10, rect.Top + 25, rect.Width - 20, 18);
        TextRenderer.DrawText(graphics, row.Label, _boldFont, titleRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(graphics, row.Detail, _smallFont, detailRect, _secondaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void DrawCard(Graphics graphics, Rectangle rect, MenuRow row, bool hovered)
    {
        var cardRect = Rectangle.Inflate(rect, -2, -3);
        using (var brush = new SolidBrush(hovered ? _cardHover : _card))
        using (var path = RoundedRect(cardRect, 8))
        {
            graphics.FillPath(brush, path);
        }

        var titleRect = new Rectangle(cardRect.Left + 12, cardRect.Top + 6, cardRect.Width - 24, 18);
        var detailRect = new Rectangle(cardRect.Left + 12, cardRect.Top + 24, cardRect.Width - 24, 16);
        TextRenderer.DrawText(graphics, row.Label, _smallBoldFont, titleRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        TextRenderer.DrawText(graphics, row.Detail, _smallFont, detailRect, _secondaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void DrawItem(Graphics graphics, Rectangle rect, MenuRow row, bool hovered)
    {
        var rowRect = Rectangle.Inflate(rect, -2, -2);
        if (hovered && row.Action is not null)
        {
            using var brush = new SolidBrush(_hover);
            using var path = RoundedRect(rowRect, 6);
            graphics.FillPath(brush, path);
        }

        var textRect = new Rectangle(rowRect.Left + 12, rowRect.Top, rowRect.Width - 24, rowRect.Height);
        if (!string.IsNullOrWhiteSpace(row.Shortcut))
        {
            var shortcutWidth = row.Shortcut == ">" ? 24 : 136;
            var shortcutRect = new Rectangle(rowRect.Right - shortcutWidth - 12, rowRect.Top, shortcutWidth, rowRect.Height);
            textRect.Width -= shortcutWidth + 18;
            TextRenderer.DrawText(graphics, row.Shortcut, _smallFont, shortcutRect, _secondaryText, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }

        TextRenderer.DrawText(graphics, row.Label, _regularFont, textRect, _primaryText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    private void CloseAfterOutsideClick()
    {
        var leftMouseDown = (Control.MouseButtons & MouseButtons.Left) == MouseButtons.Left;
        if ((DateTime.UtcNow - _shownAt).TotalMilliseconds < 220)
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
        if (disposing)
        {
            _outsideClickTimer.Dispose();
            _regularFont.Dispose();
            _boldFont.Dispose();
            _smallFont.Dispose();
            _smallBoldFont.Dispose();
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
        Card
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

        public string Label { get; }

        public string Detail { get; }

        public string Shortcut { get; }

        public Action? Action { get; }

        public int Height { get; }
    }
}

internal static class NativeMethods
{
    private static readonly IntPtr HwndTopMost = new(-1);
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpShowWindow = 0x0040;

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint uFlags);

    public static void ShowAboveEverything(Form form)
    {
        form.TopMost = true;
        form.BringToFront();
        SetWindowPos(form.Handle, HwndTopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpShowWindow);
    }
}
