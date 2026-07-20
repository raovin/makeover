using Microsoft.Win32;

namespace MacMakeover.MenuBar;

internal static class Program
{
    private const string MutexName = "Local\\MacMakeover.MenuBar";

    [STAThread]
    private static void Main(string[] args)
    {
        var preview = args.Any(arg => arg.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        var previewAll = args.Any(arg => arg.Equals("--preview-all", StringComparison.OrdinalIgnoreCase));
        var mutexName = preview ? MutexName + ".Preview" : MutexName;
        using var mutex = new Mutex(initiallyOwned: true, mutexName, out var createdNew);
        if (!createdNew) return;

        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, e) => AppLog.Write("Thread exception: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => AppLog.Write("Unhandled exception: " + e.ExceptionObject);
        using var context = new MenuBarContext(preview, previewAll);
        Application.Run(context);
    }
}

internal sealed class MenuBarContext : ApplicationContext
{
    private readonly bool _preview;
    private readonly bool _previewAll;
    private readonly SystemStateProvider _state = new();
    private readonly List<MenuBarForm> _bars = [];
    private bool _disposed;

    public MenuBarContext(bool preview, bool previewAll)
    {
        _preview = preview;
        _previewAll = previewAll;
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
            var bar = new MenuBarForm(screen, _state, _preview);
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
