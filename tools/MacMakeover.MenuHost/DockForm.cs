using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace MacMakeover.MenuHost;

internal sealed class DockForm : Form
{
    private static readonly Color TransparentChrome = Color.FromArgb(2, 4, 8);
    private readonly List<DockItem> _items;
    private readonly Dictionary<string, Image> _icons = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, bool> _running = new(StringComparer.OrdinalIgnoreCase);
    private readonly System.Windows.Forms.Timer _refreshTimer;
    private readonly ToolTip _toolTip = new();
    private int _hoverIndex = -1;
    private string _lastToolTip = string.Empty;

    private DockForm(List<DockItem> items)
    {
        _items = items.Count > 0 ? items : DockItem.FallbackItems();
        AutoScaleMode = AutoScaleMode.None;
        BackColor = TransparentChrome;
        DoubleBuffered = true;
        Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
        FormBorderStyle = FormBorderStyle.None;
        Opacity = 0.94;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TransparencyKey = TransparentChrome;
        TopMost = true;

        foreach (var item in _items)
        {
            if (!string.IsNullOrWhiteSpace(item.Key))
            {
                _icons[item.Key] = LoadIconImage(item);
            }
        }

        _refreshTimer = new System.Windows.Forms.Timer { Interval = 4000 };
        _refreshTimer.Tick += (_, _) =>
        {
            var changed = RefreshRunningState();
            PositionDock();
            NativeDockMethods.KeepAbove(this);
            if (changed)
            {
                Invalidate();
            }
        };

        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        FormClosed += (_, _) =>
        {
            NativeDockMethods.RemoveAppBar(this);
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            _refreshTimer.Dispose();
            _toolTip.Dispose();
            foreach (var icon in _icons.Values)
            {
                icon.Dispose();
            }
        };
    }

    public static DockForm Create()
    {
        return new DockForm(DockItem.Load());
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

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RefreshRunningState();
        PositionDock();
        NativeDockMethods.KeepAbove(this);
        _refreshTimer.Start();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var hit = HitTest(e.Location);
        if (hit == _hoverIndex) return;

        _hoverIndex = hit;
        Cursor = hit >= 0 ? Cursors.Hand : Cursors.Default;
        var tip = hit >= 0 ? _items[hit].DisplayName : string.Empty;
        if (!tip.Equals(_lastToolTip, StringComparison.Ordinal))
        {
            _lastToolTip = tip;
            _toolTip.SetToolTip(this, tip);
        }
        Invalidate();
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_hoverIndex < 0) return;
        _hoverIndex = -1;
        Cursor = Cursors.Default;
        Invalidate();
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button != MouseButtons.Left) return;

        var hit = HitTest(e.Location);
        if (hit < 0) return;

        _items[hit].ActivateOrLaunch();
        RefreshRunningState();
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.Clear(TransparentChrome);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;

        var shell = Rectangle.Inflate(ClientRectangle, -2, -2);
        using (var path = RoundedRect(shell, LogicalToDeviceUnits(16)))
        using (var brush = new LinearGradientBrush(shell, Color.FromArgb(66, 82, 104), Color.FromArgb(31, 37, 50), LinearGradientMode.Vertical))
        {
            e.Graphics.FillPath(brush, path);
            using var borderPen = new Pen(Color.FromArgb(90, 190, 210, 235));
            e.Graphics.DrawPath(borderPen, path);
        }

        for (var i = 0; i < _items.Count; i++)
        {
            var slot = SlotRect(i);
            var item = _items[i];
            var hovered = i == _hoverIndex;
            var running = !string.IsNullOrWhiteSpace(item.ProcessName) && _running.TryGetValue(item.ProcessName, out var isRunning) && isRunning;

            if (hovered)
            {
                var hoverRect = Rectangle.Inflate(slot, -LogicalToDeviceUnits(3), -LogicalToDeviceUnits(4));
                using var hoverBrush = new SolidBrush(Color.FromArgb(70, 255, 255, 255));
                using var hoverPath = RoundedRect(hoverRect, LogicalToDeviceUnits(10));
                e.Graphics.FillPath(hoverBrush, hoverPath);
            }

            var iconSize = hovered ? LogicalToDeviceUnits(36) : LogicalToDeviceUnits(32);
            var iconRect = new Rectangle(
                slot.Left + (slot.Width - iconSize) / 2,
                slot.Top + LogicalToDeviceUnits(7) - (hovered ? LogicalToDeviceUnits(2) : 0),
                iconSize,
                iconSize);

            if (_icons.TryGetValue(item.Key, out var icon))
            {
                e.Graphics.DrawImage(icon, iconRect);
            }
            else
            {
                DrawFallbackGlyph(e.Graphics, iconRect, item);
            }

            if (running)
            {
                var dotSize = LogicalToDeviceUnits(4);
                var dotRect = new Rectangle(slot.Left + (slot.Width - dotSize) / 2, shell.Bottom - LogicalToDeviceUnits(8), dotSize, dotSize);
                using var dotBrush = new SolidBrush(Color.FromArgb(225, 235, 244, 255));
                e.Graphics.FillEllipse(dotBrush, dotRect);
            }
        }
    }

    private void PositionDock()
    {
        var screen = Screen.PrimaryScreen?.Bounds ?? new Rectangle(0, 0, 1280, 800);
        var height = LogicalToDeviceUnits(58);
        var slot = SlotSizeFor(screen.Width);
        var width = Math.Min(screen.Width - LogicalToDeviceUnits(80), (slot * _items.Count) + LogicalToDeviceUnits(24));
        var newSize = new Size(width, height);
        if (Size != newSize)
        {
            Size = newSize;
        }

        var appBarHeight = height + LogicalToDeviceUnits(22);
        var reserved = new Rectangle(screen.Left, screen.Bottom - appBarHeight, screen.Width, appBarHeight);
        var appBarBounds = NativeDockMethods.SetBottomAppBar(this, reserved);

        var x = screen.Left + (screen.Width - Width) / 2;
        var y = appBarBounds.Bottom - Height - LogicalToDeviceUnits(10);
        if (Location.X != x || Location.Y != y)
        {
            Location = new Point(x, y);
        }
    }

    private int SlotSizeFor(int screenWidth)
    {
        var maxWidth = screenWidth - LogicalToDeviceUnits(80);
        var natural = LogicalToDeviceUnits(44);
        if (_items.Count == 0) return natural;
        return Math.Max(LogicalToDeviceUnits(34), Math.Min(natural, (maxWidth - LogicalToDeviceUnits(24)) / _items.Count));
    }

    private Rectangle SlotRect(int index)
    {
        var shell = Rectangle.Inflate(ClientRectangle, -1, -1);
        var slot = SlotSizeFor(Screen.PrimaryScreen?.Bounds.Width ?? 1280);
        var start = shell.Left + LogicalToDeviceUnits(12) + ((shell.Width - LogicalToDeviceUnits(24) - (slot * _items.Count)) / 2);
        return new Rectangle(start + (index * slot), shell.Top + LogicalToDeviceUnits(4), slot, shell.Height - LogicalToDeviceUnits(8));
    }

    private int HitTest(Point point)
    {
        for (var i = 0; i < _items.Count; i++)
        {
            if (SlotRect(i).Contains(point)) return i;
        }

        return -1;
    }

    private bool RefreshRunningState()
    {
        var changed = false;
        var runningProcesses = Process.GetProcesses()
            .Select(process =>
            {
                try
                {
                    return process.HasExited ? string.Empty : process.ProcessName;
                }
                catch
                {
                    return string.Empty;
                }
            })
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var name in _items.Select(item => item.ProcessName).Where(name => !string.IsNullOrWhiteSpace(name)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var isRunning = runningProcesses.Contains(name);
            if (!_running.TryGetValue(name, out var previous) || previous != isRunning)
            {
                _running[name] = isRunning;
                changed = true;
            }
        }

        return changed;
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        PositionDock();
        Invalidate();
    }

    private Image LoadIconImage(DockItem item)
    {
        foreach (var path in item.IconCandidatePaths())
        {
            try
            {
                var iconPath = path;
                var commaIndex = iconPath.IndexOf(',', StringComparison.Ordinal);
                if (commaIndex > 0)
                {
                    iconPath = iconPath[..commaIndex];
                }

                if (!File.Exists(iconPath)) continue;
                using var icon = Icon.ExtractAssociatedIcon(iconPath);
                if (icon is null) continue;
                return icon.ToBitmap();
            }
            catch
            {
                // Try the next icon source.
            }
        }

        using var bitmap = new Bitmap(LogicalToDeviceUnits(32), LogicalToDeviceUnits(32));
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        DrawFallbackGlyph(graphics, new Rectangle(0, 0, bitmap.Width, bitmap.Height), item);
        return (Image)bitmap.Clone();
    }

    private void DrawFallbackGlyph(Graphics graphics, Rectangle bounds, DockItem item)
    {
        using var brush = new LinearGradientBrush(bounds, Color.FromArgb(112, 139, 180), Color.FromArgb(62, 75, 102), LinearGradientMode.Vertical);
        using var path = RoundedRect(bounds, Math.Max(6, bounds.Width / 5));
        graphics.FillPath(brush, path);
        var letter = string.IsNullOrWhiteSpace(item.DisplayName) ? "?" : item.DisplayName.Trim()[0].ToString().ToUpperInvariant();
        using var font = new Font("Segoe UI", Math.Max(9, bounds.Height / 2.8f), FontStyle.Bold, GraphicsUnit.Pixel);
        TextRenderer.DrawText(graphics, letter, font, bounds, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }

    private static GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        radius = Math.Max(1, Math.Min(radius, Math.Min(bounds.Width, bounds.Height) / 2));
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
            _refreshTimer.Dispose();
            _toolTip.Dispose();
            foreach (var icon in _icons.Values)
            {
                icon.Dispose();
            }
        }

        base.Dispose(disposing);
    }
}

internal sealed class DockItem
{
    private DockItem(string displayName, string? path, string? arguments, string? workingDirectory, string? iconPath, string? umid)
    {
        DisplayName = displayName;
        Path = ResolveCurrentPath(displayName, path);
        Arguments = arguments;
        WorkingDirectory = workingDirectory;
        IconPath = iconPath;
        Umid = NullIfEmpty(umid);
        Key = $"{DisplayName}|{Path}|{Umid}";
        ProcessName = !string.IsNullOrWhiteSpace(Path) ? System.IO.Path.GetFileNameWithoutExtension(Path) : string.Empty;
    }

    public string DisplayName { get; }

    public string? Path { get; }

    public string? Arguments { get; }

    public string? WorkingDirectory { get; }

    public string? IconPath { get; }

    public string? Umid { get; }

    public string Key { get; }

    public string ProcessName { get; }

    public static List<DockItem> Load()
    {
        var candidates = CandidateStateFiles().ToList();
        var best = new List<DockItem>();

        foreach (var candidate in candidates)
        {
            var items = ParseState(candidate);
            if (items.Count > best.Count)
            {
                best = items;
            }

            if (items.Count >= 10)
            {
                Program.Log($"Dock loaded {items.Count} items from {candidate}");
                return items;
            }
        }

        if (best.Count > 0)
        {
            Program.Log($"Dock loaded fallback-best {best.Count} items.");
            return best;
        }

        Program.Log("Dock could not load Seelen WEG state; using fallback items.");
        return FallbackItems();
    }

    public static List<DockItem> FallbackItems()
    {
        return
        [
            new("Explorer", @"C:\Windows\explorer.exe", null, null, null, null),
            new("Codex", FindNewestFile(@"C:\Program Files\WindowsApps", @"OpenAI.Codex_*\app\Codex.exe"), null, null, null, "OpenAI.Codex_2p2nqsd0c76g0!App"),
            new("Claude", FindNewestFile(@"C:\Program Files\WindowsApps", @"Claude_*\app\Claude.exe"), null, null, null, "Claude_pzs8sxrjxfjjc!Claude"),
            new("Brave", @"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe", null, null, null, null),
            new("Chrome", @"C:\Program Files\Google\Chrome\Application\chrome.exe", null, null, null, "Chrome"),
            new("PowerShell", @"C:\Program Files\PowerShell\7\pwsh.exe", null, null, null, null)
        ];
    }

    public IEnumerable<string> IconCandidatePaths()
    {
        if (!string.IsNullOrWhiteSpace(IconPath)) yield return IconPath;
        if (!string.IsNullOrWhiteSpace(Path)) yield return Path;
    }

    public void ActivateOrLaunch()
    {
        try
        {
            if (TryActivateExisting()) return;

            if (!string.IsNullOrWhiteSpace(Path) && File.Exists(Path))
            {
                Process.Start(new ProcessStartInfo(Path, Arguments ?? string.Empty)
                {
                    UseShellExecute = true,
                    WorkingDirectory = !string.IsNullOrWhiteSpace(WorkingDirectory) && Directory.Exists(WorkingDirectory)
                        ? WorkingDirectory
                        : System.IO.Path.GetDirectoryName(Path) ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                });
                return;
            }

            if (!string.IsNullOrWhiteSpace(Umid))
            {
                Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{Umid}") { UseShellExecute = true });
            }
        }
        catch (Exception ex)
        {
            Program.Log($"Dock launch failed for {DisplayName}: {ex}");
        }
    }

    private bool TryActivateExisting()
    {
        if (string.IsNullOrWhiteSpace(ProcessName)) return false;

        foreach (var process in Process.GetProcessesByName(ProcessName))
        {
            try
            {
                if (process.HasExited || process.MainWindowHandle == IntPtr.Zero) continue;
                NativeDockMethods.RestoreAndActivate(process.MainWindowHandle);
                return true;
            }
            catch
            {
                // Keep looking.
            }
        }

        return false;
    }

    private static IEnumerable<string> CandidateStateFiles()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var liveDir = System.IO.Path.Combine(appData, "com.seelen.seelen-ui", "data", "seelen-weg");
        yield return System.IO.Path.Combine(liveDir, "state.yml");

        foreach (var backup in Directory.GetFiles(liveDir, "state.yml.bak*", SearchOption.TopDirectoryOnly).OrderByDescending(File.GetLastWriteTimeUtc))
        {
            yield return backup;
        }

        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var repoState = System.IO.Path.Combine(dir.FullName, "config", "seelen", "data", "seelen-weg", "state.yml");
            if (File.Exists(repoState))
            {
                yield return repoState;
                break;
            }

            dir = dir.Parent;
        }
    }

    private static List<DockItem> ParseState(string path)
    {
        try
        {
            if (!File.Exists(path)) return [];

            var items = new List<DockItem>();
            Builder? current = null;
            var inCenter = false;

            foreach (var rawLine in File.ReadLines(path))
            {
                var line = rawLine.TrimEnd();
                if (line.StartsWith("center:", StringComparison.Ordinal))
                {
                    inCenter = true;
                    continue;
                }

                if (line.StartsWith("right:", StringComparison.Ordinal))
                {
                    AddCurrent();
                    break;
                }

                if (!inCenter) continue;

                var trimmed = line.TrimStart();
                if (trimmed.StartsWith("- type:", StringComparison.Ordinal))
                {
                    AddCurrent();
                    current = trimmed.Contains("AppOrFile", StringComparison.Ordinal) ? new Builder() : null;
                    continue;
                }

                if (current is null) continue;

                if (TryValue(trimmed, "displayName", out var displayName)) current.DisplayName = displayName ?? string.Empty;
                else if (TryValue(trimmed, "umid", out var umid)) current.Umid = umid;
                else if (TryValue(trimmed, "path", out var itemPath)) current.Path = itemPath;
                else if (TryValue(trimmed, "command", out var command)) current.Command = command;
                else if (TryValue(trimmed, "args", out var args)) current.Arguments = args;
                else if (TryValue(trimmed, "workingDir", out var workingDir)) current.WorkingDirectory = workingDir;
                else if (TryValue(trimmed, "icon", out var icon)) current.IconPath = icon;
            }

            AddCurrent();
            return items
                .Where(item => !string.IsNullOrWhiteSpace(item.DisplayName))
                .GroupBy(item => item.DisplayName, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .Take(24)
                .ToList();

            void AddCurrent()
            {
                if (current is null || string.IsNullOrWhiteSpace(current.DisplayName)) return;
                var launchPath = NullIfEmpty(current.Command) ?? NullIfEmpty(current.Path);
                var dockItem = new DockItem(current.DisplayName, launchPath, current.Arguments, current.WorkingDirectory, current.IconPath, current.Umid);
                if (!string.IsNullOrWhiteSpace(dockItem.Path) || !string.IsNullOrWhiteSpace(dockItem.Umid))
                {
                    items.Add(dockItem);
                }
                current = null;
            }
        }
        catch (Exception ex)
        {
            Program.Log($"Dock state parse failed for {path}: {ex.Message}");
            return [];
        }
    }

    private static bool TryValue(string line, string key, out string? value)
    {
        value = null;
        var prefix = key + ":";
        if (!line.StartsWith(prefix, StringComparison.Ordinal)) return false;

        value = NullIfEmpty(line[prefix.Length..].Trim().Trim('"', '\''));
        return true;
    }

    private static string? ResolveCurrentPath(string displayName, string? path)
    {
        path = NullIfEmpty(path);
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
        {
            return path;
        }

        var known = displayName.ToLowerInvariant() switch
        {
            "codex" => FindNewestFile(@"C:\Program Files\WindowsApps", @"OpenAI.Codex_*\app\Codex.exe"),
            "claude" => FindNewestFile(@"C:\Program Files\WindowsApps", @"Claude_*\app\Claude.exe") ?? FindNewestFile(@"C:\Program Files\WindowsApps", @"Claude_*\app\claude.exe"),
            "microsoft teams" => FindNewestFile(@"C:\Program Files\WindowsApps", @"MSTeams_*\ms-teams.exe"),
            "outlook" => FindNewestFile(@"C:\Program Files\WindowsApps", @"Microsoft.OutlookForWindows_*\olk.exe"),
            "bitwarden" => FindNewestFile(@"C:\Program Files\WindowsApps", @"8bitSolutionsLLC.bitwardendesktop_*\app\Bitwarden.exe"),
            _ => null
        };

        return known ?? path;
    }

    private static string? FindNewestFile(string root, string pattern)
    {
        try
        {
            if (!Directory.Exists(root)) return null;
            var parts = pattern.Replace('/', '\\').Split('\\', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return null;

            IEnumerable<string> dirs = [root];
            foreach (var part in parts.Take(parts.Length - 1))
            {
                dirs = dirs.SelectMany(dir => EnumerateMatchingDirectories(dir, part)).ToList();
            }

            var filePattern = parts[^1];
            return dirs.SelectMany(dir => EnumerateMatchingFiles(dir, filePattern))
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
        }
        catch
        {
            return null;
        }
    }

    private static IEnumerable<string> EnumerateMatchingDirectories(string root, string pattern)
    {
        try
        {
            return Directory.EnumerateDirectories(root, pattern, SearchOption.TopDirectoryOnly);
        }
        catch
        {
            return [];
        }
    }

    private static IEnumerable<string> EnumerateMatchingFiles(string root, string pattern)
    {
        try
        {
            return Directory.EnumerateFiles(root, pattern, SearchOption.TopDirectoryOnly);
        }
        catch
        {
            return [];
        }
    }

    private static string? NullIfEmpty(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Equals("null", StringComparison.OrdinalIgnoreCase)) return null;
        return value;
    }

    private sealed class Builder
    {
        public string DisplayName { get; set; } = string.Empty;
        public string? Path { get; set; }
        public string? Command { get; set; }
        public string? Arguments { get; set; }
        public string? WorkingDirectory { get; set; }
        public string? IconPath { get; set; }
        public string? Umid { get; set; }
    }
}

internal static class NativeDockMethods
{
    private static readonly IntPtr HwndTopMost = new(-1);
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const int AbmNew = 0x00000000;
    private const int AbmRemove = 0x00000001;
    private const int AbmQueryPos = 0x00000002;
    private const int AbmSetPos = 0x00000003;
    private const int AbeBottom = 3;
    private static readonly Dictionary<IntPtr, int> AppBarMessages = new();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern IntPtr SHAppBarMessage(int dwMessage, ref AppBarData pData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int RegisterWindowMessage(string lpString);

    public static void RestoreAndActivate(IntPtr handle)
    {
        ShowWindow(handle, 9); // SW_RESTORE
        SetForegroundWindow(handle);
    }

    public static void KeepAbove(Form form)
    {
        if (form.IsDisposed || form.Disposing) return;
        SetWindowPos(form.Handle, HwndTopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate | SwpShowWindow);
    }

    public static Rectangle SetBottomAppBar(Form form, Rectangle desired)
    {
        if (form.IsDisposed || form.Disposing || form.Handle == IntPtr.Zero) return desired;

        if (!AppBarMessages.TryGetValue(form.Handle, out var callbackMessage))
        {
            callbackMessage = RegisterWindowMessage("MacMakeover.Dock.AppBar");
            var newData = AppBarData.For(form.Handle, callbackMessage, desired);
            SHAppBarMessage(AbmNew, ref newData);
            AppBarMessages[form.Handle] = callbackMessage;
        }

        var query = AppBarData.For(form.Handle, callbackMessage, desired);
        query.uEdge = AbeBottom;
        SHAppBarMessage(AbmQueryPos, ref query);

        query.rc.Left = desired.Left;
        query.rc.Right = desired.Right;
        query.rc.Top = query.rc.Bottom - desired.Height;
        query.uEdge = AbeBottom;
        SHAppBarMessage(AbmSetPos, ref query);

        return new Rectangle(query.rc.Left, query.rc.Top, query.rc.Right - query.rc.Left, query.rc.Bottom - query.rc.Top);
    }

    public static void RemoveAppBar(Form form)
    {
        if (form.Handle == IntPtr.Zero || !AppBarMessages.Remove(form.Handle, out var callbackMessage)) return;

        var data = AppBarData.For(form.Handle, callbackMessage, Rectangle.Empty);
        SHAppBarMessage(AbmRemove, ref data);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uCallbackMessage;
        public int uEdge;
        public NativeRect rc;
        public IntPtr lParam;

        public static AppBarData For(IntPtr handle, int callbackMessage, Rectangle bounds)
        {
            return new AppBarData
            {
                cbSize = Marshal.SizeOf<AppBarData>(),
                hWnd = handle,
                uCallbackMessage = callbackMessage,
                uEdge = AbeBottom,
                rc = new NativeRect
                {
                    Left = bounds.Left,
                    Top = bounds.Top,
                    Right = bounds.Right,
                    Bottom = bounds.Bottom
                },
                lParam = IntPtr.Zero
            };
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
