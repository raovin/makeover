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
        var previewPower = args.FirstOrDefault(arg => arg.StartsWith("--preview-power=", StringComparison.OrdinalIgnoreCase))?
            .Split('=', 2)[1];
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
        var pluggedIn = battery with { BatteryPercent = 100, OnAcPower = true, PowerMode = PowerModeKind.Balanced };
        return SystemStateProvider.ClassifyPowerMode(new Guid("961cc777-2547-4f9d-8174-7d86181b8a7a")) == PowerModeKind.Saver &&
               SystemStateProvider.ClassifyPowerMode(Guid.Empty) == PowerModeKind.Balanced &&
               SystemStateProvider.ClassifyPowerMode(new Guid("381b4222-f694-41f0-9685-ff5bb260df2e")) == PowerModeKind.Balanced &&
               SystemStateProvider.ClassifyPowerMode(new Guid("ded574b5-45a0-4f42-8737-46345c09c238")) == PowerModeKind.Performance &&
               MenuBarForm.PowerSourceLabel(battery) == "Battery 42%" &&
               MenuBarForm.PowerModeLabel(battery.PowerMode) == "Power saver" &&
               MenuBarForm.PowerSourceLabel(charging) == "Charging 42%" &&
               MenuBarForm.PowerModeLabel(charging.PowerMode) == "High performance" &&
               MenuBarForm.PowerSourceLabel(pluggedIn) == "Plugged in 100%" &&
               MenuBarForm.PowerModeLabel(pluggedIn.PowerMode) == "Balanced";
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
