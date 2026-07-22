using Microsoft.Win32;
using System.Diagnostics;

namespace MacMakeover.MenuBar;

internal sealed record TrayAppSnapshot(
    string Key,
    string Name,
    string ExecutablePath,
    bool Promoted);

internal static class TrayAppProvider
{
    private const string NotifyIconRegistryPath = @"Control Panel\NotifyIconSettings";
    private static readonly object Gate = new();
    private static DateTime _registryReadAt;
    private static IReadOnlyList<TrayRegistration> _registrations = [];
    private static DateTime _captureReadAt;
    private static IReadOnlyList<TrayAppSnapshot> _capture = [];

    public static IReadOnlyList<TrayAppSnapshot> Capture()
    {
        lock (Gate)
        {
            if ((DateTime.UtcNow - _captureReadAt).TotalSeconds < 5) return _capture;
            _captureReadAt = DateTime.UtcNow;
            var registrations = Registrations();
            var runningPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var process in Process.GetProcesses())
            {
                using (process)
                {
                    try
                    {
                        if (!string.IsNullOrWhiteSpace(process.MainModule?.FileName))
                        {
                            runningPaths.Add(Path.GetFullPath(process.MainModule.FileName));
                        }
                    }
                    catch (System.ComponentModel.Win32Exception) { }
                    catch (InvalidOperationException) { }
                }
            }

            return _capture = registrations
                .Where(item => runningPaths.Contains(item.ExecutablePath))
                .GroupBy(item => item.ExecutablePath, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.OrderByDescending(item => item.Promoted).First())
                .OrderBy(item => item.Name.Equals("Awake & Available", StringComparison.OrdinalIgnoreCase) ? 0 : item.Promoted ? 1 : 2)
                .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
                .Select(item => new TrayAppSnapshot(item.Key, item.Name, item.ExecutablePath, item.Promoted))
                .ToArray();
        }
    }

    internal static string ExpandExecutablePath(string path)
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        return Environment.ExpandEnvironmentVariables(path)
            .Replace("{6D809377-6AF0-444B-8957-A3773F02200E}", Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), StringComparison.OrdinalIgnoreCase)
            .Replace("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}", Path.Combine(windows, "System32"), StringComparison.OrdinalIgnoreCase)
            .Replace("{F38BF404-1D43-42F2-9305-67DE0B28FC23}", windows, StringComparison.OrdinalIgnoreCase);
    }

    private static IReadOnlyList<TrayRegistration> Registrations()
    {
        lock (Gate)
        {
            if ((DateTime.UtcNow - _registryReadAt).TotalSeconds < 15) return _registrations;
            _registryReadAt = DateTime.UtcNow;
            var registrations = new List<TrayRegistration>();
            try
            {
                using var root = Registry.CurrentUser.OpenSubKey(NotifyIconRegistryPath);
                if (root is null) return _registrations = [];
                foreach (var keyName in root.GetSubKeyNames())
                {
                    using var key = root.OpenSubKey(keyName);
                    var tooltip = key?.GetValue("InitialTooltip") as string;
                    var rawPath = key?.GetValue("ExecutablePath") as string;
                    if (string.IsNullOrWhiteSpace(tooltip) || string.IsNullOrWhiteSpace(rawPath)) continue;
                    var executablePath = ExpandExecutablePath(rawPath);
                    var processName = Path.GetFileNameWithoutExtension(executablePath);
                    if (string.IsNullOrWhiteSpace(processName) || IsShellOwned(processName)) continue;
                    var promoted = key?.GetValue("IsPromoted", 0) is int promotedValue && promotedValue != 0;
                    registrations.Add(new TrayRegistration(
                        keyName,
                        tooltip.Trim(),
                        executablePath,
                        promoted));
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            {
                AppLog.Write("Tray registry read failed: " + ex.Message);
            }
            return _registrations = registrations;
        }
    }

    private static bool IsShellOwned(string processName) =>
        processName.Equals("explorer", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("SecurityHealthSystray", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("Taskmgr", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("MoNotificationUx", StringComparison.OrdinalIgnoreCase);

    private sealed record TrayRegistration(
        string Key,
        string Name,
        string ExecutablePath,
        bool Promoted);
}

internal sealed class TrayIconCache : IDisposable
{
    private readonly Dictionary<string, Image?> _images = new(StringComparer.OrdinalIgnoreCase);

    public Image? Get(TrayAppSnapshot app)
    {
        if (_images.TryGetValue(app.Key, out var cached)) return cached;
        Image? image = null;
        if (File.Exists(app.ExecutablePath))
        {
            try
            {
                using var icon = Icon.ExtractAssociatedIcon(app.ExecutablePath);
                if (icon is not null) image = new Bitmap(icon.ToBitmap());
            }
            catch (ArgumentException) { }
        }

        // Some apps update their tray artwork independently of the executable.
        // Use Windows' saved snapshot only when the executable has no icon of its own.
        if (image is not null)
        {
            _images[app.Key] = image;
            return image;
        }
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey($@"Control Panel\NotifyIconSettings\{app.Key}");
            if (key?.GetValue("IconSnapshot") is byte[] png && png.Length > 0)
            {
                using var stream = new MemoryStream(png);
                using var source = Image.FromStream(stream);
                image = new Bitmap(source);
            }
        }
        catch (ArgumentException) { }
        catch (IOException) { }

        _images[app.Key] = image;
        return image;
    }

    public void Dispose()
    {
        foreach (var image in _images.Values) image?.Dispose();
        _images.Clear();
    }
}

internal static class TrayAppLauncher
{
    public static void Activate(TrayAppSnapshot app)
    {
        var processName = Path.GetFileNameWithoutExtension(app.ExecutablePath);
        foreach (var process in Process.GetProcessesByName(processName))
        {
            using (process)
            {
                try
                {
                    if (!string.Equals(process.MainModule?.FileName, app.ExecutablePath, StringComparison.OrdinalIgnoreCase)) continue;
                }
                catch (System.ComponentModel.Win32Exception) { continue; }
                catch (InvalidOperationException) { continue; }
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                if (NativeMethods.IsIconic(process.MainWindowHandle))
                {
                    NativeMethods.ShowWindow(process.MainWindowHandle, NativeMethods.SwRestore);
                }
                if (NativeMethods.SetForegroundWindow(process.MainWindowHandle)) return;
            }
        }
        Process.Start(new ProcessStartInfo(app.ExecutablePath) { UseShellExecute = true });
    }
}

internal sealed class TrayMenuColorTable : ProfessionalColorTable
{
    private static readonly Color Surface = Color.FromArgb(32, 36, 43);
    private static readonly Color Hover = Color.FromArgb(54, 61, 72);
    private static readonly Color Edge = Color.FromArgb(82, 93, 107);

    public override Color ToolStripDropDownBackground => Surface;
    public override Color ImageMarginGradientBegin => Surface;
    public override Color ImageMarginGradientMiddle => Surface;
    public override Color ImageMarginGradientEnd => Surface;
    public override Color MenuItemSelected => Hover;
    public override Color MenuItemBorder => Edge;
    public override Color ToolStripBorder => Edge;
}
