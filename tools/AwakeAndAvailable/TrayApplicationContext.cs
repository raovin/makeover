using System.Drawing;

namespace AwakeAndAvailable;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly System.Windows.Forms.Timer _activityTimer;
    private readonly System.Windows.Forms.Timer _showMenuTimer;
    private readonly EventWaitHandle _showMenuEvent;
    private readonly AppSettings _settings;
    private TeamsActivityMode _teamsMode = TeamsActivityMode.Off;
    private int _jiggleDirection = 1;
    private bool _preventSleep;
    private bool _isCapturingPoint;

    internal TrayApplicationContext(EventWaitHandle showMenuEvent)
    {
        _showMenuEvent = showMenuEvent;
        _settings = AppSettings.Load();
        _preventSleep = _settings.PreventSleep;

        _activityTimer = new System.Windows.Forms.Timer();
        _activityTimer.Tick += (_, _) => PerformTeamsActivity();
        UpdateTimerInterval();

        _trayIcon = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application,
            Text = "Awake & Available",
            Visible = true
        };
        _trayIcon.DoubleClick += (_, _) => TogglePreventSleep();
        _showMenuTimer = new System.Windows.Forms.Timer { Interval = 150 };
        _showMenuTimer.Tick += (_, _) =>
        {
            if (!_showMenuEvent.WaitOne(0)) return;
            _trayIcon.ContextMenuStrip?.Show(Cursor.Position);
        };

        ApplyPowerState();
        RebuildMenu();
        _showMenuTimer.Start();
        ShowBalloon("Awake & Available is running", "Use the notification-area icon to control sleep and Teams activity.");
    }

    private void RebuildMenu()
    {
        var menu = new ContextMenuStrip();

        menu.Items.Add(new ToolStripMenuItem(StatusText) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());

        var preventSleep = new ToolStripMenuItem("Prevent PC sleep")
        {
            Checked = _preventSleep,
            CheckOnClick = false
        };
        preventSleep.Click += (_, _) => TogglePreventSleep();
        menu.Items.Add(preventSleep);

        var teamsMenu = new ToolStripMenuItem("Keep Teams active");
        teamsMenu.DropDownItems.Add(CreateModeItem("Off", TeamsActivityMode.Off));
        teamsMenu.DropDownItems.Add(CreateModeItem("Mouse jiggle (recommended)", TeamsActivityMode.MouseJiggle));
        teamsMenu.DropDownItems.Add(CreateModeItem("Click saved safe point", TeamsActivityMode.SafePointClick));
        menu.Items.Add(teamsMenu);

        var pointText = _settings.SafePointX.HasValue
            ? $"Capture safe click point in 3 seconds… (currently {_settings.SafePointX}, {_settings.SafePointY})"
            : "Capture safe click point in 3 seconds…";
        var capture = new ToolStripMenuItem(pointText);
        capture.Click += (_, _) => BeginPointCapture();
        menu.Items.Add(capture);

        var intervalMenu = new ToolStripMenuItem("Activity interval");
        foreach (var seconds in new[] { 30, 60, 120, 240 })
        {
            var label = seconds < 60 ? $"{seconds} seconds" : $"{seconds / 60} minute{(seconds == 60 ? "" : "s")}";
            var item = new ToolStripMenuItem(label) { Checked = _settings.IntervalSeconds == seconds, Tag = seconds };
            item.Click += (_, _) => SetInterval((int)item.Tag!);
            intervalMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(intervalMenu);

        menu.Items.Add(new ToolStripSeparator());
        var about = new ToolStripMenuItem("About / safety notes…");
        about.Click += (_, _) => MessageBox.Show(
            "Mouse activity is best-effort and cannot override Microsoft Teams or company presence policies.\n\n" +
            "Click mode acts on the saved screen position only while Windows reports that you are idle. " +
            "Use a harmless blank area and recapture it after moving windows or changing displays.",
            "Awake & Available", MessageBoxButtons.OK, MessageBoxIcon.Information);
        menu.Items.Add(about);

        var quit = new ToolStripMenuItem("Exit Awake & Available");
        quit.Click += (_, _) => ExitThread();
        menu.Items.Add(quit);

        var oldMenu = _trayIcon.ContextMenuStrip;
        _trayIcon.ContextMenuStrip = menu;
        oldMenu?.Dispose();
        _trayIcon.Text = StatusText.Length <= 63 ? StatusText : "Awake & Available";
    }

    private ToolStripMenuItem CreateModeItem(string text, TeamsActivityMode mode)
    {
        var item = new ToolStripMenuItem(text) { Checked = _teamsMode == mode, Tag = mode };
        item.Click += (_, _) => SetTeamsMode((TeamsActivityMode)item.Tag!);
        return item;
    }

    private string StatusText =>
        $"{(_preventSleep ? "PC awake" : "Normal sleep")} • " +
        (_teamsMode switch
        {
            TeamsActivityMode.MouseJiggle => "Teams mouse jiggle",
            TeamsActivityMode.SafePointClick => "Teams safe-point click",
            _ => "Teams activity off"
        });

    private void TogglePreventSleep()
    {
        _preventSleep = !_preventSleep;
        _settings.PreventSleep = _preventSleep;
        _settings.Save();
        ApplyPowerState();
        RebuildMenu();
    }

    private void ApplyPowerState()
    {
        var state = NativeMethods.ExecutionState.Continuous;
        if (_preventSleep)
            state |= NativeMethods.ExecutionState.SystemRequired | NativeMethods.ExecutionState.DisplayRequired;

        var result = NativeMethods.SetThreadExecutionState(state);
        if (result == 0)
        {
            _preventSleep = false;
            _settings.PreventSleep = false;
            _settings.Save();
            MessageBox.Show("Windows rejected the request to prevent sleep.", "Awake & Available",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void SetTeamsMode(TeamsActivityMode mode)
    {
        if (mode == TeamsActivityMode.SafePointClick && !_settings.SafePointX.HasValue)
        {
            MessageBox.Show("Capture a harmless safe click point first.", "Awake & Available",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (mode == TeamsActivityMode.SafePointClick)
        {
            var result = MessageBox.Show(
                "This will periodically left-click the saved screen position when you are idle. " +
                "Confirm that the point is harmless and will not send messages or activate controls.",
                "Enable click activity?", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
            if (result != DialogResult.OK) return;
        }

        _teamsMode = mode;
        _activityTimer.Enabled = mode != TeamsActivityMode.Off;
        RebuildMenu();
    }

    private void SetInterval(int seconds)
    {
        _settings.IntervalSeconds = seconds;
        _settings.Save();
        UpdateTimerInterval();
        RebuildMenu();
    }

    private void UpdateTimerInterval()
    {
        _activityTimer.Interval = Math.Clamp(_settings.IntervalSeconds, 10, 3600) * 1000;
    }

    private void BeginPointCapture()
    {
        if (_isCapturingPoint) return;
        _isCapturingPoint = true;
        ShowBalloon("Capturing in 3 seconds", "Move the pointer to a harmless blank area and leave it there until you hear the beep.");

        var captureTimer = new System.Windows.Forms.Timer { Interval = 3000 };
        captureTimer.Tick += (_, _) =>
        {
            captureTimer.Stop();
            captureTimer.Dispose();
            var point = Cursor.Position;
            _settings.SafePointX = point.X;
            _settings.SafePointY = point.Y;
            _settings.Save();
            _isCapturingPoint = false;
            System.Media.SystemSounds.Beep.Play();
            ShowBalloon("Safe click point captured", $"Saved screen position {point.X}, {point.Y}. No click was performed.");
            RebuildMenu();
        };
        captureTimer.Start();
    }

    private void PerformTeamsActivity()
    {
        if (_teamsMode == TeamsActivityMode.Off) return;

        // Do not interfere while the user is actively operating the computer.
        var idleThreshold = TimeSpan.FromSeconds(Math.Max(5, _settings.IntervalSeconds - 5));
        if (NativeMethods.GetIdleTime() < idleThreshold) return;

        if (_teamsMode == TeamsActivityMode.MouseJiggle)
        {
            var current = Cursor.Position;
            var virtualScreen = SystemInformation.VirtualScreen;
            var nextX = Math.Clamp(current.X + _jiggleDirection, virtualScreen.Left, virtualScreen.Right - 1);
            if (nextX == current.X)
            {
                _jiggleDirection *= -1;
                nextX = Math.Clamp(current.X + _jiggleDirection, virtualScreen.Left, virtualScreen.Right - 1);
            }
            Cursor.Position = new Point(nextX, current.Y);
            _jiggleDirection *= -1;
            return;
        }

        var clickPoint = new Point(_settings.SafePointX!.Value, _settings.SafePointY!.Value);
        if (!SystemInformation.VirtualScreen.Contains(clickPoint))
        {
            _teamsMode = TeamsActivityMode.Off;
            _activityTimer.Stop();
            ShowBalloon("Click activity stopped", "The saved point is no longer on an active display. Capture it again.");
            RebuildMenu();
            return;
        }

        var original = Cursor.Position;
        Cursor.Position = clickPoint;
        NativeMethods.mouse_event(NativeMethods.MouseEventLeftDown, 0, 0, 0, 0);
        NativeMethods.mouse_event(NativeMethods.MouseEventLeftUp, 0, 0, 0, 0);

        var restoreTimer = new System.Windows.Forms.Timer { Interval = 75 };
        restoreTimer.Tick += (_, _) =>
        {
            restoreTimer.Stop();
            restoreTimer.Dispose();
            Cursor.Position = original;
        };
        restoreTimer.Start();
    }

    private void ShowBalloon(string title, string text)
    {
        _trayIcon.BalloonTipTitle = title;
        _trayIcon.BalloonTipText = text;
        _trayIcon.BalloonTipIcon = ToolTipIcon.Info;
        _trayIcon.ShowBalloonTip(4000);
    }

    protected override void ExitThreadCore()
    {
        _activityTimer.Stop();
        _showMenuTimer.Stop();
        NativeMethods.SetThreadExecutionState(NativeMethods.ExecutionState.Continuous);
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _activityTimer.Dispose();
        _showMenuTimer.Dispose();
        base.ExitThreadCore();
    }
}
