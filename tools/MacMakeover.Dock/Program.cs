using Microsoft.Win32;
using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace MacMakeover.Dock;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Any(value => value.Equals("--probe-window", StringComparison.OrdinalIgnoreCase)))
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new Form
            {
                Text = "MacMakeover Dynamic Dock Probe",
                StartPosition = FormStartPosition.Manual,
                Location = new Point(-30000, -30000),
                Size = new Size(320, 180),
                ShowInTaskbar = true
            });
            return;
        }
        if (args.Any(value => value.Equals("--regression-test", StringComparison.OrdinalIgnoreCase)))
        {
            ApplicationConfiguration.Initialize();
            Environment.ExitCode = DockRegressionTests.Run();
            return;
        }
        var preview = args.Any(value => value.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        var previewAll = args.Any(value => value.Equals("--preview-all", StringComparison.OrdinalIgnoreCase));
        if (args.Length >= 2 && args[0].Equals("--export-icons", StringComparison.OrdinalIgnoreCase))
        {
            ExportIcons(args[1]);
            return;
        }
        if (args.Length >= 2 && args[0].Equals("--snapshot-running", StringComparison.OrdinalIgnoreCase))
        {
            var pinned = PinnedApp.Load();
            var snapshot = RunningAppSnapshot.Capture(pinned).Select(app => new
            {
                app.Key,
                app.Name,
                app.ProcessName,
                app.ExecutablePath,
                Windows = app.Windows.Select(window => window.ToInt64()).ToArray()
            });
            File.WriteAllText(args[1], JsonSerializer.Serialize(snapshot, new JsonSerializerOptions { WriteIndented = true }));
            return;
        }
        if (args.Any(value => value.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                var apps = PinnedApp.Load();
                if (apps.Count == 0) { Environment.ExitCode = 2; return; }
                foreach (var app in apps)
                {
                    using var icon = app.LoadIcon(56);
                    if (icon is null) { Environment.ExitCode = 3; return; }
                }
                _ = RunningAppSnapshot.Capture(apps);
                Environment.ExitCode = 0;
            }
            catch { Environment.ExitCode = 4; }
            return;
        }
        if (args.Any(value => value.Equals("--shutdown", StringComparison.OrdinalIgnoreCase)))
        {
            var eventName = preview ? "Local\\MacMakeover.Dock.Preview.Exit" : "Local\\MacMakeover.Dock.Exit";
            try { EventWaitHandle.OpenExisting(eventName).Set(); } catch (WaitHandleCannotBeOpenedException) { }
            return;
        }
        var previewHover = args.Any(value => value.Equals("--preview-hover", StringComparison.OrdinalIgnoreCase));
        using var mutex = new Mutex(true, preview ? "Local\\MacMakeover.Dock.Preview" : "Local\\MacMakeover.Dock", out var first);
        if (!first) return;
        using var exit = new EventWaitHandle(false, EventResetMode.AutoReset, preview ? "Local\\MacMakeover.Dock.Preview.Exit" : "Local\\MacMakeover.Dock.Exit");
        ApplicationConfiguration.Initialize();
        Application.Run(new DockContext(preview, previewAll, previewHover, exit));
    }

    private static void ExportIcons(string directory)
    {
        Directory.CreateDirectory(directory);
        foreach (var app in PinnedApp.Load())
        {
            using var icon = app.LoadIcon(84);
            if (icon is null) continue;
            var fileName = string.Concat(app.Name.Select(character =>
                Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
            icon.Save(Path.Combine(directory, fileName + ".png"), ImageFormat.Png);
        }
    }
}

internal static class DockRegressionTests
{
    public static int Run()
    {
        var probePath = Path.Combine(AppContext.BaseDirectory, "MacMakeover.QaProbe.exe");
        var pinStatePath = Path.Combine(Path.GetTempPath(), "MacMakeover", $"dock-pins-qa-{Environment.ProcessId}.json");
        try
        {
            Environment.SetEnvironmentVariable("MACMAKEOVER_DOCK_PIN_STATE", pinStatePath);
            File.Copy(Environment.ProcessPath!, probePath, true);
            if (!TestDynamicApp(probePath)) return 2;
            if (!TestPinnedApp(probePath)) return 3;
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally
        {
            try { File.Delete(probePath); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            try { File.Delete(pinStatePath); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static bool TestDynamicApp(string probePath)
    {
        using var probe = StartProbe(probePath);
        var snapshot = WaitForSnapshot(probe);
        if (snapshot is null) return false;

        using var item = new DockItem(snapshot, 28);
        using var menu = DockForm.BuildContextMenu(item);
        if (!HasCommands(menu, "Open", "Pin to Dock", "Close All Windows")) return false;
        if (item.IsPinned || !item.CanPin || !item.CanClose) return false;

        menu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Pin to Dock").PerformClick();
        var persisted = PinnedApp.Load()
            .FirstOrDefault(app => app.MatchesProcess(snapshot.ProcessName));
        if (persisted is null || !persisted.IsUserPin) return false;
        using (var persistedItem = new DockItem(persisted, 28))
        using (var persistedMenu = DockForm.BuildContextMenu(persistedItem))
        {
            if (!HasCommands(persistedMenu, "Open", "Remove from Dock", "Close All Windows")) return false;
            persistedMenu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Remove from Dock").PerformClick();
        }
        if (PinnedApp.Load().Any(app => app.MatchesProcess(snapshot.ProcessName))) return false;

        NativeMethods.ShowWindow(snapshot.Windows[0], NativeMethods.SwMinimize);
        if (!WaitUntil(() => NativeMethods.IsIconic(snapshot.Windows[0]), TimeSpan.FromSeconds(2))) return false;
        menu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Open").PerformClick();
        if (!WaitUntil(() => !NativeMethods.IsIconic(snapshot.Windows[0]), TimeSpan.FromSeconds(2))) return false;
        menu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Close All Windows").PerformClick();
        return probe.WaitForExit(3000);
    }

    private static bool TestPinnedApp(string probePath)
    {
        using var probe = StartProbe(probePath);
        var snapshot = WaitForSnapshot(probe);
        if (snapshot is null) return false;

        var pinned = new PinnedApp
        {
            Name = "MacMakeover QA Probe",
            Patterns = [],
            ExecutablePath = probePath,
            ProcessNames = [snapshot.ProcessName],
            IsUserPin = true
        };
        using var item = new DockItem(pinned, 28);
        using var menu = DockForm.BuildContextMenu(item);
        if (!HasCommands(menu, "Open", "Remove from Dock", "Close All Windows")) return false;
        if (!item.IsPinned || item.CanPin || !item.CanClose) return false;

        NativeMethods.ShowWindow(snapshot.Windows[0], NativeMethods.SwMinimize);
        if (!WaitUntil(() => NativeMethods.IsIconic(snapshot.Windows[0]), TimeSpan.FromSeconds(2))) return false;
        menu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Open").PerformClick();
        if (!WaitUntil(() => !NativeMethods.IsIconic(snapshot.Windows[0]), TimeSpan.FromSeconds(2))) return false;
        menu.Items.Cast<ToolStripItem>().First(entry => entry.Text == "Close All Windows").PerformClick();
        return probe.WaitForExit(3000);
    }

    private static Process StartProbe(string probePath)
    {
        var process = Process.Start(new ProcessStartInfo(probePath, "--probe-window")
        {
            UseShellExecute = false
        }) ?? throw new InvalidOperationException("Could not start Dock QA probe.");
        if (!WaitUntil(() =>
            {
                process.Refresh();
                return process.HasExited || process.MainWindowHandle != IntPtr.Zero;
            }, TimeSpan.FromSeconds(5)) || process.HasExited)
        {
            process.Dispose();
            throw new InvalidOperationException("Dock QA probe did not expose a window.");
        }
        return process;
    }

    private static RunningAppSnapshot? WaitForSnapshot(Process process)
    {
        RunningAppSnapshot? result = null;
        WaitUntil(() =>
        {
            process.Refresh();
            if (process.HasExited) return true;
            result = RunningAppSnapshot.Capture(PinnedApp.Load())
                .FirstOrDefault(snapshot => snapshot.ProcessName.Equals(process.ProcessName, StringComparison.OrdinalIgnoreCase));
            return result is not null;
        }, TimeSpan.FromSeconds(5));
        return result;
    }

    private static bool HasCommands(ContextMenuStrip menu, params string[] expected)
    {
        var labels = menu.Items.Cast<ToolStripItem>()
            .Where(item => item is not ToolStripSeparator)
            .Select(item => item.Text)
            .ToArray();
        return expected.All(label => labels.Contains(label, StringComparer.Ordinal));
    }

    private static bool WaitUntil(Func<bool> predicate, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        do
        {
            Application.DoEvents();
            if (predicate()) return true;
            Thread.Sleep(40);
        } while (DateTime.UtcNow < deadline);
        return predicate();
    }
}

internal sealed class DockContext : ApplicationContext
{
    private readonly bool _preview;
    private readonly bool _previewAll;
    private readonly bool _previewHover;
    private readonly List<DockForm> _forms = [];
    private readonly List<WorkAreaGapForm> _gapForms = [];
    private readonly List<IntPtr> _taskbars = [];
    private readonly System.Windows.Forms.Timer _taskbarGuard = new() { Interval = 1500 };
    private readonly RegisteredWaitHandle _exitRegistration;
    private bool _rebuilding;
    private int _displayRebuildPending;
    private bool _exiting;

    public DockContext(bool preview, bool previewAll, bool previewHover, EventWaitHandle exit)
    {
        _preview = preview;
        _previewAll = previewAll;
        _previewHover = previewHover;
        if (!preview)
        {
            HideWindowsTaskbars();
            _taskbarGuard.Tick += (_, _) => MaintainShellSurfaces();
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
        var screens = _preview && !_previewAll
            ? Screen.AllScreens.Where(screen => screen.Primary)
            : Screen.AllScreens.AsEnumerable();
        foreach (var screen in screens)
        {
            if (!_preview)
            {
                var gapForm = new WorkAreaGapForm(screen);
                _gapForms.Add(gapForm);
                gapForm.Show();
            }
            var form = new DockForm(screen, apps, _preview, _previewHover);
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
        foreach (var gapForm in _gapForms) gapForm.EnsureReserved();
    }

    private void MaintainShellSurfaces()
    {
        HideWindowsTaskbars();
        foreach (var form in _forms) form.EnsureVisible();
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
        foreach (var taskbar in _taskbars) NativeMethods.ShowWindow(taskbar, NativeMethods.SwShow);
        base.ExitThreadCore();
    }
}

internal sealed class WorkAreaGapForm : Form
{
    private const int LogicalGap = 8;
    private const int ReservationAnchorSize = 1;
    private const int WmNcHitTest = 0x0084;
    private static readonly IntPtr HtTransparent = new(-1);
    private readonly Screen _screen;
    private readonly uint _callbackMessage;
    private readonly uint _taskbarCreatedMessage;
    private readonly System.Windows.Forms.Timer _settleTimer = new() { Interval = 500 };
    private bool _registered;
    private bool _positionPending;
    private int _remainingSettleAttempts;
    private int _stableSettleSamples;

    public WorkAreaGapForm(Screen screen)
    {
        _screen = screen;
        _callbackMessage = NativeMethods.RegisterWindowMessage($"MacMakeover.Dock.WorkAreaGap.{Environment.ProcessId}.{screen.DeviceName}");
        _taskbarCreatedMessage = NativeMethods.RegisterWindowMessage("TaskbarCreated");
        AutoScaleMode = AutoScaleMode.None;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = false;
        Enabled = false;
        Opacity = 0;
        Location = new Point(screen.Bounds.Left, screen.Bounds.Bottom - 1);
        Size = new Size(ReservationAnchorSize, ReservationAnchorSize);
        _settleTimer.Tick += (_, _) => SettlePosition();
        Shown += (_, _) =>
        {
            RegisterAndPosition();
            BeginSettle();
        };
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
        if (!_registered)
        {
            var registration = CreateAppBarData();
            _registered = NativeMethods.SHAppBarMessage(NativeMethods.AbmNew, ref registration) != UIntPtr.Zero;
            if (!_registered) return;
        }
        PositionAppBar();
    }

    private void PositionAppBar()
    {
        if (!_registered || IsDisposed || !IsHandleCreated) return;
        var previousDpiContext = NativeMethods.SetThreadDpiAwarenessContext(
            NativeMethods.DpiAwarenessContextPerMonitorAwareV2);
        try
        {
            var data = CreateAppBarData();
            var targetDpi = DisplayScale.DpiFor(_screen, DeviceDpi);
            var visualScale = DisplayScale.For(_screen, targetDpi);
            var visualDockHeight = (int)Math.Round(48 * visualScale);
            // Hidden taskbar windows remain alive for Explorer ownership but no longer
            // reserve work area on current Windows builds. Own the full dock height and
            // breathing room here so maximized applications can never cover the dock.
            var gap = visualDockHeight + (int)Math.Round(LogicalGap * visualScale);
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
            NativeMethods.SetWindowPos(
                Handle,
                NativeMethods.HwndBottom,
                data.Bounds.Left,
                data.Bounds.Bottom - ReservationAnchorSize,
                ReservationAnchorSize,
                ReservationAnchorSize,
                NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow);
        }
        finally
        {
            if (previousDpiContext != IntPtr.Zero)
            {
                NativeMethods.SetThreadDpiAwarenessContext(previousDpiContext);
            }
        }
    }

    protected override void WndProc(ref Message message)
    {
        if (_taskbarCreatedMessage != 0 && message.Msg == _taskbarCreatedMessage)
        {
            _registered = false;
            QueuePosition(register: true);
        }
        else if (_callbackMessage != 0 && message.Msg == _callbackMessage &&
                 message.WParam.ToInt32() == NativeMethods.AbnPosChanged)
        {
            QueuePosition(register: false);
        }
        if (message.Msg == WmNcHitTest)
        {
            message.Result = HtTransparent;
            return;
        }
        base.WndProc(ref message);
    }

    private void QueuePosition(bool register)
    {
        if (_positionPending || IsDisposed) return;
        _positionPending = true;
        try
        {
            BeginInvoke(new Action(() =>
            {
                _positionPending = false;
                if (register)
                {
                    RegisterAndPosition();
                    BeginSettle();
                }
                else
                {
                    PositionAppBar();
                }
            }));
        }
        catch (InvalidOperationException)
        {
            _positionPending = false;
        }
    }

    private void BeginSettle()
    {
        _remainingSettleAttempts = 20;
        _stableSettleSamples = 0;
        _settleTimer.Start();
    }

    private void SettlePosition()
    {
        if (IsDisposed || !_registered)
        {
            _settleTimer.Stop();
            return;
        }

        var expectedReservation = ExpectedReservation();
        var actualReservation = _screen.Bounds.Bottom - _screen.WorkingArea.Bottom;
        if (actualReservation == expectedReservation)
        {
            if (++_stableSettleSamples >= 2) _settleTimer.Stop();
            return;
        }

        _stableSettleSamples = 0;
        if (_remainingSettleAttempts % 2 == 0) ReRegisterAppBar();
        else PositionAppBar();
        if (--_remainingSettleAttempts <= 0) _settleTimer.Stop();
    }

    public void EnsureReserved()
    {
        if (!_registered || _settleTimer.Enabled || IsDisposed) return;
        var actualReservation = _screen.Bounds.Bottom - _screen.WorkingArea.Bottom;
        if (actualReservation != ExpectedReservation()) BeginSettle();
    }

    private int ExpectedReservation()
    {
        var targetDpi = DisplayScale.DpiFor(_screen, DeviceDpi);
        var visualScale = DisplayScale.For(_screen, targetDpi);
        return (int)Math.Round(48 * visualScale) +
               (int)Math.Round(LogicalGap * visualScale);
    }

    private void ReRegisterAppBar()
    {
        if (_registered && IsHandleCreated)
        {
            var removal = CreateAppBarData();
            NativeMethods.SHAppBarMessage(NativeMethods.AbmRemove, ref removal);
            _registered = false;
        }
        RegisterAndPosition();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _settleTimer.Stop();
            _settleTimer.Dispose();
        }
        if (_registered && IsHandleCreated)
        {
            var data = CreateAppBarData();
            NativeMethods.SHAppBarMessage(NativeMethods.AbmRemove, ref data);
            _registered = false;
        }
        base.Dispose(disposing);
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
    private IReadOnlyList<PinnedApp> _pinnedApps;
    private readonly List<DockItem> _items = [];
    private readonly List<DockItem> _pinnedItems = [];
    private readonly Dictionary<string, DockItem> _runningItems = new(StringComparer.OrdinalIgnoreCase);
    private readonly ToolTip _toolTip = new() { InitialDelay = 450, ReshowDelay = 100, AutoPopDelay = 5000 };
    private readonly System.Windows.Forms.Timer _stateTimer = new() { Interval = 1000 };
    private Rectangle _frame;
    private float _visualScale = 1F;
    private int _hoveredItem = -1;

    public DockForm(Screen screen, IReadOnlyList<PinnedApp> apps, bool preview, bool previewHover)
    {
        _screen = screen;
        _preview = preview;
        _pinnedApps = apps;
        if (preview) Text = "MacMakeover Dock Preview";
        AutoScaleMode = AutoScaleMode.None;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(16, 18, 28);
        DoubleBuffered = true;
        foreach (var app in apps)
        {
            var item = new DockItem(app, IconSize);
            _items.Add(item);
            _pinnedItems.Add(item);
        }
        if (preview && previewHover) _hoveredItem = Math.Min(4, _items.Count - 1);
        MouseMove += OnDockMouseMove;
        MouseLeave += OnDockMouseLeave;
        MouseUp += OnDockMouseUp;
        Shown += (_, _) =>
        {
            Location = _screen.Bounds.Location;
            BeginInvoke(new Action(() =>
            {
                RefreshDockState();
                PositionDock();
            }));
        };
        DpiChanged += (_, _) => BeginInvoke(new Action(PositionDock));
        _stateTimer.Tick += (_, _) => RefreshDockState();
        _stateTimer.Start();
        DockPinStore.Changed += OnPinsChanged;
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ExStyle |= NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate; return cp; } }

    public void EnsureVisible()
    {
        if (_preview || IsDisposed || !IsHandleCreated) return;
        var extendedStyle = NativeMethods.GetWindowLongPtr(Handle, NativeMethods.GwlExStyle).ToInt64();
        var needsRepair = !NativeMethods.IsWindowVisible(Handle) ||
                          (extendedStyle & NativeMethods.WsExTopMost) == 0;
        var foreground = NativeMethods.GetForegroundWindow();
        if (!needsRepair && foreground != IntPtr.Zero && foreground != Handle &&
            NativeMethods.GetWindowRect(foreground, out var foregroundBounds))
        {
            needsRepair = IsAbove(foreground, Handle) &&
                          foregroundBounds.Left <= _screen.Bounds.Left &&
                          foregroundBounds.Top <= _screen.Bounds.Top &&
                          foregroundBounds.Right >= _screen.Bounds.Right &&
                          foregroundBounds.Bottom >= _screen.Bounds.Bottom;
        }
        if (!needsRepair) return;
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HwndTopMost,
            Left,
            Top,
            Width,
            Height,
            NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow);
    }

    private static bool IsAbove(IntPtr candidate, IntPtr window)
    {
        for (var current = NativeMethods.GetWindow(window, NativeMethods.GwHwndPrev);
             current != IntPtr.Zero;
             current = NativeMethods.GetWindow(current, NativeMethods.GwHwndPrev))
        {
            if (current == candidate) return true;
        }
        return false;
    }

    private void PositionDock()
    {
        var targetDpi = DisplayScale.DpiFor(_screen, DeviceDpi);
        var scale = DisplayScale.For(_screen, targetDpi);
        _visualScale = scale;
        var height = (int)Math.Round(LogicalHeight * scale);
        var bottom = _preview ? _screen.WorkingArea.Bottom : _screen.Bounds.Bottom;
        Location = new Point(_screen.Bounds.Left, bottom - height);
        Size = new Size(_screen.Bounds.Width, height);
        var maximumFrameWidth = Width - (int)Math.Round(16 * scale);
        var horizontalPadding = (int)Math.Round(HorizontalPadding * 2 * scale);
        var preferredSlotWidth = (int)Math.Round(SlotWidth * scale);
        var availableSlotWidth = Math.Max(1, maximumFrameWidth - horizontalPadding) / Math.Max(1, _items.Count);
        var slotWidth = Math.Min(preferredSlotWidth, Math.Max(1, availableSlotWidth));
        var contentWidth = _items.Count * slotWidth;
        var frameWidth = Math.Min(maximumFrameWidth, contentWidth + horizontalPadding);
        var frameHeight = (int)Math.Round(42 * scale);
        if ((height - frameHeight) % 2 != 0) frameHeight--;
        _frame = new Rectangle((Width - frameWidth) / 2, (Height - frameHeight) / 2, frameWidth, frameHeight);
        var itemHeight = frameHeight - (int)Math.Round(4 * scale);
        var itemLeft = _frame.Left + (int)Math.Round(HorizontalPadding * scale);
        var itemTop = _frame.Top + (int)Math.Round(2 * scale);
        for (var index = 0; index < _items.Count; index++)
        {
            _items[index].SetLayout(
                new Rectangle(itemLeft + index * slotWidth, itemTop, slotWidth, itemHeight),
                scale);
        }
        using var path = Rounded(_frame, (int)Math.Round(14 * scale));
        Region = new Region(path);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        WallpaperSlice.Draw(e.Graphics, ClientRectangle, _screen.Bounds, Bounds.Top);
        if (_frame.Width <= 0 || _frame.Height <= 0) return;
        using var framePath = Rounded(_frame, (int)Math.Round(14 * _visualScale));
        using var brush = new LinearGradientBrush(_frame, Color.FromArgb(250, 38, 44, 52), Color.FromArgb(252, 15, 18, 23), LinearGradientMode.Vertical);
        e.Graphics.FillPath(brush, framePath);
        var edgeInset = (int)Math.Round(15 * _visualScale);
        using var top = new Pen(Color.FromArgb(150, 137, 151, 166), Math.Max(1, _visualScale));
        e.Graphics.DrawLine(top, _frame.Left + edgeInset, _frame.Top + 1, _frame.Right - edgeInset, _frame.Top + 1);
        using var edge = new Pen(Color.FromArgb(110, 83, 96, 110), Math.Max(1, _visualScale));
        e.Graphics.DrawArc(edge, _frame.Left, _frame.Top, _frame.Height, _frame.Height, 90, 180);
        e.Graphics.DrawArc(edge, _frame.Right - _frame.Height, _frame.Top, _frame.Height, _frame.Height, 270, 180);
        e.Graphics.DrawLine(edge, _frame.Left + _frame.Height / 2, _frame.Bottom - 1, _frame.Right - _frame.Height / 2, _frame.Bottom - 1);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        for (var index = 0; index < _items.Count; index++)
        {
            _items[index].Draw(e.Graphics, index == _hoveredItem);
        }
    }

    private void OnDockMouseMove(object? sender, MouseEventArgs e)
    {
        var next = _items.FindIndex(item => item.Bounds.Contains(e.Location));
        if (next == _hoveredItem) return;
        _hoveredItem = next;
        Cursor = next >= 0 ? Cursors.Hand : Cursors.Default;
        _toolTip.SetToolTip(this, next >= 0 ? _items[next].Name : string.Empty);
        Invalidate();
    }

    private void OnDockMouseLeave(object? sender, EventArgs e)
    {
        if (_hoveredItem < 0) return;
        _hoveredItem = -1;
        Cursor = Cursors.Default;
        _toolTip.SetToolTip(this, string.Empty);
        Invalidate();
    }

    private void OnDockMouseUp(object? sender, MouseEventArgs e)
    {
        var item = _items.FirstOrDefault(candidate => candidate.Bounds.Contains(e.Location));
        if (item is null) return;

        if (e.Button == MouseButtons.Left)
        {
            item.ActivateOrLaunch();
        }
        else if (e.Button == MouseButtons.Right)
        {
            var menu = BuildContextMenu(item);
            menu.Closed += (_, _) => menu.Dispose();
            menu.Show(this, e.Location);
        }
    }

    internal static ContextMenuStrip BuildContextMenu(DockItem item)
    {
        var menu = new ContextMenuStrip
        {
            BackColor = Color.FromArgb(30, 35, 46),
            ForeColor = Color.White,
            ShowImageMargin = false
        };
        menu.Items.Add("Open", null, (_, _) => item.ActivateOrLaunch());
        menu.Items.Add(new ToolStripSeparator());
        if (item.IsPinned)
        {
            menu.Items.Add("Remove from Dock", null, (_, _) => item.Unpin());
        }
        else if (item.CanPin)
        {
            menu.Items.Add("Pin to Dock", null, (_, _) => item.Pin());
        }
        if (item.CanClose)
        {
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Close All Windows", null, (_, _) =>
            {
                if (!item.Close()) System.Media.SystemSounds.Exclamation.Play();
            });
        }
        return menu;
    }

    private void OnPinsChanged()
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired)
        {
            try { BeginInvoke(new Action(ReloadPins)); }
            catch (InvalidOperationException) { }
            return;
        }
        ReloadPins();
    }

    private void ReloadPins()
    {
        foreach (var item in _items) item.Dispose();
        _items.Clear();
        _pinnedItems.Clear();
        _runningItems.Clear();
        _pinnedApps = PinnedApp.Load();
        foreach (var app in _pinnedApps)
        {
            var item = new DockItem(app, IconSize);
            _items.Add(item);
            _pinnedItems.Add(item);
        }
        _hoveredItem = -1;
        RefreshDockState();
        PositionDock();
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

    private void RefreshDockState()
    {
        var visualChanged = false;
        var runningProcesses = SnapshotProcesses();
        foreach (var item in _pinnedItems)
        {
            visualChanged |= item.RefreshPinnedState(runningProcesses);
        }

        var layoutChanged = false;
        var snapshots = RunningAppSnapshot.Capture(_pinnedApps);
        var currentKeys = new HashSet<string>(snapshots.Select(snapshot => snapshot.Key), StringComparer.OrdinalIgnoreCase);
        foreach (var staleKey in _runningItems.Keys.Where(key => !currentKeys.Contains(key)).ToArray())
        {
            var stale = _runningItems[staleKey];
            _runningItems.Remove(staleKey);
            _items.Remove(stale);
            stale.Dispose();
            layoutChanged = true;
        }

        foreach (var snapshot in snapshots)
        {
            if (_runningItems.TryGetValue(snapshot.Key, out var existing))
            {
                visualChanged |= existing.UpdateRunningApp(snapshot);
                continue;
            }

            var item = new DockItem(snapshot, IconSize);
            _runningItems.Add(snapshot.Key, item);
            _items.Add(item);
            layoutChanged = true;
        }

        if (layoutChanged) PositionDock();
        else if (visualChanged) Invalidate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            DockPinStore.Changed -= OnPinsChanged;
            _stateTimer.Dispose();
            _toolTip.Dispose();
            foreach (var item in _items) item.Dispose();
        }
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
            var displayEdge = Screen.AllScreens
                .Select(screen => Math.Max(screen.Bounds.Width, screen.Bounds.Height))
                .DefaultIfEmpty(1920)
                .Max();
            var scale = Math.Min(1d, displayEdge / (double)Math.Max(source.Width, source.Height));
            var width = Math.Max(1, (int)Math.Round(source.Width * scale));
            var height = Math.Max(1, (int)Math.Round(source.Height * scale));
            var wallpaper = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            using var graphics = Graphics.FromImage(wallpaper);
            graphics.CompositingQuality = CompositingQuality.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.DrawImage(source, new Rectangle(0, 0, width, height));
            return wallpaper;
        }
        catch { return null; }
    }
}

internal static class DisplayScale
{
    public static int DpiFor(Screen screen, int fallback)
    {
        try
        {
            var center = new NativeMethods.NativePoint
            {
                X = screen.Bounds.Left + screen.Bounds.Width / 2,
                Y = screen.Bounds.Top + screen.Bounds.Height / 2
            };
            var monitor = NativeMethods.MonitorFromPoint(center, 2);
            if (monitor != IntPtr.Zero &&
                NativeMethods.GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 &&
                dpiX >= 96)
            {
                return (int)dpiX;
            }
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
        return Math.Max(96, fallback);
    }

    public static float For(Screen screen, int dpi) =>
        Math.Max(Math.Max(1F, dpi / 96F), screen.Primary ? 1F : 1.5F);
}

internal sealed class DockItem : IDisposable
{
    private readonly PinnedApp? _pinnedApp;
    private RunningApp? _runningApp;
    private readonly Image? _icon;
    private float _visualScale = 1F;
    private bool _running;

    public DockItem(PinnedApp app, int iconSize)
    {
        _pinnedApp = app;
        _icon = app.LoadIcon(iconSize * 3);
    }

    public DockItem(RunningAppSnapshot app, int iconSize)
    {
        _runningApp = new RunningApp(app);
        _icon = _runningApp.LoadIcon(iconSize * 3);
        _running = true;
    }

    public string Name => _pinnedApp?.Name ?? _runningApp?.Name ?? string.Empty;
    public Rectangle Bounds { get; private set; }
    public bool IsRunning => _running;
    public bool IsPinned => _pinnedApp is not null;
    public bool CanPin => _runningApp is { CanPin: true };
    public bool CanClose => _pinnedApp?.HasClosableWindows() ?? _runningApp?.HasClosableWindows() ?? false;

    public bool RefreshPinnedState(IReadOnlySet<string> processes)
    {
        if (_pinnedApp is null) return false;
        var running = _pinnedApp.IsRunning(processes);
        if (running == _running) return false;
        _running = running;
        return true;
    }

    public bool UpdateRunningApp(RunningAppSnapshot snapshot)
    {
        if (_runningApp is null) return false;
        return _runningApp.Update(snapshot);
    }

    public void SetLayout(Rectangle bounds, float visualScale)
    {
        Bounds = bounds;
        _visualScale = visualScale;
    }

    public void ActivateOrLaunch()
    {
        if (_pinnedApp is not null) _pinnedApp.ActivateOrLaunch();
        else _runningApp?.Activate();
    }

    public bool Close()
    {
        return _pinnedApp is not null ? _pinnedApp.Close() : _runningApp?.Close() ?? false;
    }

    public void Pin()
    {
        if (_runningApp is not null) DockPinStore.Pin(_runningApp);
    }

    public void Unpin()
    {
        if (_pinnedApp is not null) DockPinStore.Unpin(_pinnedApp);
    }

    public void Draw(Graphics graphics, bool hovered)
    {
        var scale = _visualScale;
        if (_icon != null)
        {
            var preferredSize = (int)Math.Round((hovered ? 30 : 28) * scale);
            var size = Math.Max(4, Math.Min(preferredSize, Bounds.Width - (int)Math.Round(6 * scale)));
            var x = Bounds.Left + (Bounds.Width - size) / 2;
            var y = Bounds.Top + (Bounds.Height - size) / 2 - (int)Math.Round((hovered ? 3 : 2) * scale);
            graphics.DrawImage(_icon, new Rectangle(x, y, size, size));
        }
        else
        {
            var size = Math.Max(4, Math.Min((int)Math.Round(28 * scale), Bounds.Width - (int)Math.Round(6 * scale)));
            var x = Bounds.Left + (Bounds.Width - size) / 2;
            var y = Bounds.Top + (Bounds.Height - size) / 2 - (int)Math.Round(2 * scale);
            using var tile = new SolidBrush(Color.FromArgb(255, 57, 66, 78));
            graphics.FillEllipse(tile, x, y, size, size);
            using var font = new Font("Segoe UI Semibold", 9.5f * scale, FontStyle.Bold, GraphicsUnit.Pixel);
            TextRenderer.DrawText(graphics, string.Concat(Name.Where(char.IsLetter).Take(2)).ToUpperInvariant(), font, new Rectangle(x, y, size, size), Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
        if (_running)
        {
            var dot = (int)Math.Round(3 * scale);
            using var brush = new SolidBrush(Color.FromArgb(225, 207, 221, 233));
            graphics.FillEllipse(
                brush,
                Bounds.Left + (Bounds.Width - dot) / 2,
                Bounds.Bottom - (int)Math.Round(5 * scale),
                dot,
                dot);
        }
    }

    public void Dispose() => _icon?.Dispose();
}

internal sealed record RunningAppSnapshot(
    string Key,
    string Name,
    string ProcessName,
    string? ExecutablePath,
    IntPtr[] Windows)
{
    private static readonly HashSet<string> ExcludedProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "MacMakeover.Dock", "MacMakeover.MenuBar", "MacMakeover.MenuHost",
        "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost", "TextInputHost",
        "LockApp", "LogonUI", "OpenWith"
    };

    public static IReadOnlyList<RunningAppSnapshot> Capture(IReadOnlyList<PinnedApp> pinnedApps)
    {
        var groups = new Dictionary<string, RunningAppAccumulator>(StringComparer.OrdinalIgnoreCase);
        NativeMethods.EnumWindows((window, _) =>
        {
            if (!IsTaskbarWindow(window)) return true;
            NativeMethods.GetWindowThreadProcessId(window, out var processId);
            if (processId == 0 || processId == Environment.ProcessId) return true;

            try
            {
                using var process = Process.GetProcessById((int)processId);
                var processName = process.ProcessName;
                if (ExcludedProcesses.Contains(processName) || pinnedApps.Any(app => app.MatchesProcess(processName))) return true;

                string? executablePath = null;
                try { executablePath = process.MainModule?.FileName; }
                catch (System.ComponentModel.Win32Exception) { }
                catch (InvalidOperationException) { }

                var title = WindowTitle(window);
                var name = DisplayName(processName, executablePath, title);
                // ApplicationFrameHost can own several unrelated packaged apps at once.
                // Keep each titled surface distinct, then remove duplicate host entries
                // when the app also exposes its concrete process below.
                var key = processName.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase)
                    ? $"{processName}:{title}"
                    : string.IsNullOrWhiteSpace(executablePath) ? processName : executablePath;
                if (!groups.TryGetValue(key, out var group))
                {
                    group = new RunningAppAccumulator(key, name, processName, executablePath);
                    groups.Add(key, group);
                }
                group.Windows.Add(window);
            }
            catch (ArgumentException) { }
            catch (InvalidOperationException) { }
            return true;
        }, IntPtr.Zero);

        var concreteNames = groups.Values
            .Where(group => !group.ProcessName.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase))
            .Select(group => group.Name)
            .ToHashSet(StringComparer.CurrentCultureIgnoreCase);
        return groups.Values
            .Where(group => !group.ProcessName.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase) ||
                            !concreteNames.Contains(group.Name))
            .OrderBy(group => group.Name, StringComparer.CurrentCultureIgnoreCase)
            .Select(group => new RunningAppSnapshot(
                group.Key,
                group.Name,
                group.ProcessName,
                group.ExecutablePath,
                group.Windows.ToArray()))
            .ToArray();
    }

    internal static bool IsTaskbarWindow(IntPtr window)
    {
        if (window == IntPtr.Zero || !NativeMethods.IsWindowVisible(window)) return false;
        var extendedStyle = NativeMethods.GetWindowLongPtr(window, NativeMethods.GwlExStyle).ToInt64();
        if ((extendedStyle & NativeMethods.WsExToolWindow) != 0) return false;
        if (NativeMethods.GetWindow(window, NativeMethods.GwOwner) != IntPtr.Zero &&
            (extendedStyle & NativeMethods.WsExAppWindow) == 0) return false;
        if (NativeMethods.DwmGetWindowAttribute(window, NativeMethods.DwmwaCloaked, out var cloaked, sizeof(int)) == 0 && cloaked != 0) return false;
        return !string.IsNullOrWhiteSpace(WindowTitle(window));
    }

    internal static string WindowClass(IntPtr window)
    {
        var className = new StringBuilder(256);
        return NativeMethods.GetClassName(window, className, className.Capacity) > 0
            ? className.ToString()
            : string.Empty;
    }

    private static string WindowTitle(IntPtr window)
    {
        var length = NativeMethods.GetWindowTextLength(window);
        if (length <= 0) return string.Empty;
        var title = new StringBuilder(length + 1);
        NativeMethods.GetWindowText(window, title, title.Capacity);
        return title.ToString().Trim();
    }

    private static string DisplayName(string processName, string? executablePath, string title)
    {
        var knownName = processName.ToLowerInvariant() switch
        {
            "msedge" => "Microsoft Edge",
            "notepad" => "Notepad",
            "mspaint" => "Paint",
            "snippingtool" => "Snipping Tool",
            "systemsettings" => "Settings",
            "applicationframehost" => string.IsNullOrWhiteSpace(title) ? "Windows App" : title,
            _ => null
        };
        if (knownName is not null) return knownName;

        if (!string.IsNullOrWhiteSpace(executablePath))
        {
            try
            {
                var version = FileVersionInfo.GetVersionInfo(executablePath);
                if (!string.IsNullOrWhiteSpace(version.FileDescription))
                {
                    var description = version.FileDescription.Trim();
                    return description.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                        ? Path.GetFileNameWithoutExtension(description)
                        : description;
                }
                if (!string.IsNullOrWhiteSpace(version.ProductName)) return version.ProductName.Trim();
            }
            catch (FileNotFoundException) { }
        }
        return string.IsNullOrWhiteSpace(title) ? processName : title;
    }

    private sealed class RunningAppAccumulator(string key, string name, string processName, string? executablePath)
    {
        public string Key { get; } = key;
        public string Name { get; } = name;
        public string ProcessName { get; } = processName;
        public string? ExecutablePath { get; } = executablePath;
        public List<IntPtr> Windows { get; } = [];
    }
}

internal sealed class RunningApp
{
    private IntPtr[] _windows;

    public RunningApp(RunningAppSnapshot snapshot)
    {
        Name = snapshot.Name;
        ProcessName = snapshot.ProcessName;
        ExecutablePath = snapshot.ExecutablePath;
        _windows = snapshot.Windows;
    }

    public string Name { get; private set; }
    public string ProcessName { get; }
    public string? ExecutablePath { get; }
    public bool CanPin =>
        !ProcessName.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase) &&
        !string.IsNullOrWhiteSpace(ExecutablePath) &&
        File.Exists(ExecutablePath);
    public bool HasClosableWindows() => _windows.Any(NativeMethods.IsWindow);

    public bool Update(RunningAppSnapshot snapshot)
    {
        var changed = !string.Equals(Name, snapshot.Name, StringComparison.Ordinal) ||
                      !_windows.SequenceEqual(snapshot.Windows);
        Name = snapshot.Name;
        _windows = snapshot.Windows;
        return changed;
    }

    public void Activate()
    {
        foreach (var window in _windows.Where(NativeMethods.IsWindow))
        {
            if (NativeMethods.IsIconic(window)) NativeMethods.ShowWindow(window, NativeMethods.SwRestore);
            if (NativeMethods.SetForegroundWindow(window)) return;
        }
    }

    public bool Close()
    {
        var succeeded = false;
        foreach (var window in _windows.Where(NativeMethods.IsWindow))
        {
            succeeded |= NativeMethods.PostMessage(window, NativeMethods.WmClose, IntPtr.Zero, IntPtr.Zero);
        }
        return succeeded;
    }

    public Image? LoadIcon(int size)
    {
        if (!string.IsNullOrWhiteSpace(ExecutablePath) && File.Exists(ExecutablePath))
        {
            var fileIcon = PinnedApp.LoadFileIcon(ExecutablePath, size);
            if (fileIcon is not null) return fileIcon;
        }

        foreach (var window in _windows)
        {
            var iconHandle = NativeMethods.SendMessage(window, NativeMethods.WmGetIcon, new IntPtr(NativeMethods.IconBig2), IntPtr.Zero);
            if (iconHandle == IntPtr.Zero) iconHandle = NativeMethods.SendMessage(window, NativeMethods.WmGetIcon, new IntPtr(NativeMethods.IconBig), IntPtr.Zero);
            if (iconHandle == IntPtr.Zero) iconHandle = NativeMethods.GetClassLongPtr(window, NativeMethods.GclpHIcon);
            if (iconHandle == IntPtr.Zero) continue;
            using var icon = Icon.FromHandle(iconHandle);
            return new Bitmap(icon.ToBitmap(), new Size(size, size));
        }
        return null;
    }
}

internal sealed class DockPinState
{
    public List<UserDockPin> Added { get; init; } = [];
    public List<string> Removed { get; init; } = [];
}

internal sealed record UserDockPin(string Name, string ProcessName, string ExecutablePath);

internal static class DockPinStore
{
    private static readonly object Sync = new();
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };
    private static string StatePath =>
        Environment.GetEnvironmentVariable("MACMAKEOVER_DOCK_PIN_STATE") ??
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacMakeover",
            "config",
            "dock-pins.json");

    public static event Action? Changed;

    public static DockPinState Load()
    {
        lock (Sync)
        {
            if (!File.Exists(StatePath)) return new DockPinState();
            try
            {
                return JsonSerializer.Deserialize<DockPinState>(File.ReadAllText(StatePath), JsonOptions)
                       ?? new DockPinState();
            }
            catch (JsonException)
            {
                return new DockPinState();
            }
            catch (IOException)
            {
                return new DockPinState();
            }
        }
    }

    public static void Pin(RunningApp app)
    {
        if (!app.CanPin || string.IsNullOrWhiteSpace(app.ExecutablePath)) return;
        lock (Sync)
        {
            var state = Load();
            state.Removed.RemoveAll(name => name.Equals(app.Name, StringComparison.OrdinalIgnoreCase));
            state.Added.RemoveAll(pin =>
                pin.Name.Equals(app.Name, StringComparison.OrdinalIgnoreCase) ||
                pin.ExecutablePath.Equals(app.ExecutablePath, StringComparison.OrdinalIgnoreCase));
            state.Added.Add(new UserDockPin(app.Name, app.ProcessName, app.ExecutablePath));
            Save(state);
        }
        Changed?.Invoke();
    }

    public static void Unpin(PinnedApp app)
    {
        lock (Sync)
        {
            var state = Load();
            state.Added.RemoveAll(pin => pin.Name.Equals(app.Name, StringComparison.OrdinalIgnoreCase));
            if (!state.Removed.Contains(app.Name, StringComparer.OrdinalIgnoreCase))
            {
                state.Removed.Add(app.Name);
            }
            Save(state);
        }
        Changed?.Invoke();
    }

    private static void Save(DockPinState state)
    {
        var directory = Path.GetDirectoryName(StatePath)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = StatePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions));
        File.Move(temporaryPath, StatePath, true);
    }
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
    public string? ExecutablePath { get; init; }
    public required string[] ProcessNames { get; init; }
    public bool IsUserPin { get; init; }

    public static IReadOnlyList<PinnedApp> Load()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "native-taskbar-pins.json")));
        var pinned = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Internet Explorer", "Quick Launch", "User Pinned", "TaskBar");
        var state = DockPinStore.Load();
        var removed = state.Removed.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var builtIn = document.RootElement.GetProperty("pins").EnumerateArray().Select(item =>
        {
            var name = item.GetProperty("name").GetString()!;
            var patterns = item.GetProperty("taskbandPatterns").EnumerateArray().Select(p => p.GetString()!).ToArray();
            var shortcut = Directory.Exists(pinned) ? Directory.EnumerateFiles(pinned, "*.lnk").FirstOrDefault(path => patterns.Any(p => Path.GetFileName(path).Contains(Path.GetFileNameWithoutExtension(p), StringComparison.OrdinalIgnoreCase))) : null;
            return new PinnedApp
            {
                Name = name,
                AppId = item.TryGetProperty("appId", out var id) && id.ValueKind != JsonValueKind.Null ? id.GetString() : null,
                Patterns = patterns,
                Shortcut = shortcut,
                ProcessNames = Processes.GetValueOrDefault(name, [])
            };
        }).Where(app => !removed.Contains(app.Name));
        var added = state.Added
            .Where(pin => !removed.Contains(pin.Name) && !string.IsNullOrWhiteSpace(pin.ExecutablePath))
            .Select(pin => new PinnedApp
            {
                Name = pin.Name,
                Patterns = [],
                ExecutablePath = pin.ExecutablePath,
                ProcessNames = [pin.ProcessName],
                IsUserPin = true
            });
        return builtIn
            .Concat(added)
            .DistinctBy(app => app.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public bool IsRunning(IReadOnlySet<string> processes) => ProcessNames.Any(processes.Contains);

    public bool MatchesProcess(string processName) => ProcessNames.Contains(processName, StringComparer.OrdinalIgnoreCase);

    public void ActivateOrLaunch()
    {
        foreach (var processName in ProcessNames)
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                if (NativeMethods.IsIconic(process.MainWindowHandle)) NativeMethods.ShowWindow(process.MainWindowHandle, NativeMethods.SwRestore);
                if (NativeMethods.SetForegroundWindow(process.MainWindowHandle)) return;
            }
        }
        var target = ExecutablePath ?? Shortcut ?? (AppId is null ? null : $"shell:AppsFolder\\{AppId}");
        if (target is null) return;
        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
    }

    public bool Close()
    {
        var succeeded = false;
        foreach (var window in ClosableWindows())
        {
            succeeded |= NativeMethods.PostMessage(window, NativeMethods.WmClose, IntPtr.Zero, IntPtr.Zero);
        }
        return succeeded;
    }

    public bool HasClosableWindows() => ClosableWindows().Length > 0;

    private IntPtr[] ClosableWindows()
    {
        var processIds = new HashSet<uint>();
        var currentSessionId = Process.GetCurrentProcess().SessionId;
        foreach (var processName in ProcessNames)
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                using (process)
                {
                    try
                    {
                        if (process.SessionId == currentSessionId) processIds.Add((uint)process.Id);
                    }
                    catch (InvalidOperationException) { }
                }
            }
        }
        if (processIds.Count == 0) return [];

        var windows = new List<IntPtr>();
        NativeMethods.EnumWindows((window, _) =>
        {
            NativeMethods.GetWindowThreadProcessId(window, out var processId);
            if (processIds.Contains(processId) &&
                RunningAppSnapshot.IsTaskbarWindow(window) &&
                (!Name.Equals("File Explorer", StringComparison.OrdinalIgnoreCase) ||
                 RunningAppSnapshot.WindowClass(window) is "CabinetWClass" or "ExploreWClass"))
            {
                windows.Add(window);
            }
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }

    public Image? LoadIcon(int size)
    {
        var overridePath = Path.Combine(AppContext.BaseDirectory, "Assets", "Dock", $"{Name}.png");
        if (File.Exists(overridePath))
        {
            try
            {
                using var overrideImage = Image.FromFile(overridePath);
                return new Bitmap(overrideImage);
            }
            catch (ArgumentException) { }
        }
        if (Name.Equals("File Explorer", StringComparison.OrdinalIgnoreCase))
        {
            var explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
            return LoadFileIcon(explorer, size);
        }
        if (AppId is not null)
        {
            var packaged = LoadShellItemIcon($"shell:AppsFolder\\{AppId}", size);
            if (packaged is not null) return packaged;
        }
        var source = ExecutablePath;
        source ??= Shortcut is null ? null : ResolveShortcutTarget(Shortcut);
        source ??= Shortcut;
        source ??= AppId is null ? null : $"shell:AppsFolder\\{AppId}";
        if (source is null) return null;
        return LoadShellItemIcon(source, size) ?? LoadFileIcon(source, size);
    }

    internal static Image? LoadFileIcon(string source, int size)
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
            try { return CopyShellBitmap(bitmap, size); }
            finally { NativeMethods.DeleteObject(bitmap); }
        }
        catch { return null; }
        finally { if (factory is not null && Marshal.IsComObject(factory)) Marshal.FinalReleaseComObject(factory); }
    }

    private static Image? CopyShellBitmap(IntPtr handle, int size)
    {
        if (NativeMethods.GetObject(handle, Marshal.SizeOf<NativeMethods.BitmapObject>(), out var source) == 0 ||
            source.Width <= 0 || source.Height == 0)
        {
            return null;
        }

        var width = source.Width;
        var height = Math.Abs(source.Height);
        using var preserved = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        var pixels = preserved.LockBits(
            new Rectangle(0, 0, width, height),
            ImageLockMode.WriteOnly,
            PixelFormat.Format32bppPArgb);
        var deviceContext = NativeMethods.GetDC(IntPtr.Zero);
        try
        {
            var info = new NativeMethods.BitmapInfo
            {
                Header = new NativeMethods.BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<NativeMethods.BitmapInfoHeader>(),
                    Width = width,
                    Height = -height,
                    Planes = 1,
                    BitCount = 32,
                    Compression = 0,
                    SizeImage = (uint)(Math.Abs(pixels.Stride) * height)
                }
            };
            if (deviceContext == IntPtr.Zero ||
                NativeMethods.GetDIBits(deviceContext, handle, 0, (uint)height, pixels.Scan0, ref info, 0) == 0)
            {
                return null;
            }
        }
        finally
        {
            if (deviceContext != IntPtr.Zero) NativeMethods.ReleaseDC(IntPtr.Zero, deviceContext);
            preserved.UnlockBits(pixels);
        }

        var result = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
        using var graphics = Graphics.FromImage(result);
        graphics.CompositingMode = CompositingMode.SourceCopy;
        graphics.CompositingQuality = CompositingQuality.HighQuality;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        graphics.DrawImage(preserved, new Rectangle(0, 0, size, size));
        return result;
    }
}
