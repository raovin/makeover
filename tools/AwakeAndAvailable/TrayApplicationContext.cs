using System.Drawing;

namespace AwakeAndAvailable;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly System.Windows.Forms.Timer _activityTimer;
    private readonly System.Windows.Forms.Timer _scheduleTimer;
    private readonly System.Windows.Forms.Timer _showMenuTimer;
    private readonly EventWaitHandle _showMenuEvent;
    private readonly AppSettings _settings;
    private TeamsActivityMode _teamsMode;
    private bool _preventSleep;
    private bool _isCapturingPoint;
    private DateTime? _lastPulse;
    private bool _lastPulseAccepted;
    private bool _pulseFailureNotified;
    private bool _menuRefreshPending;
    private bool _isExiting;
    private DateTime _lastMenuClosedUtc = DateTime.MinValue;

    internal TrayApplicationContext(EventWaitHandle showMenuEvent)
    {
        _showMenuEvent = showMenuEvent;
        _settings = AppSettings.Load();
        _settings.TeamsMode = ScheduleEngine.NormalizePersistentMode(_settings.TeamsMode);
        var initialDecision = ScheduleEngine.Resolve(_settings, DateTimeOffset.UtcNow);
        _preventSleep = initialDecision.PreventSleep;
        _teamsMode = initialDecision.TeamsMode;
        if (!initialDecision.ManualOverrideActive && _settings.ManualOverrideUntilUtc.HasValue)
            _settings.ClearManualOverride();
        _settings.Save();

        _activityTimer = new System.Windows.Forms.Timer();
        _activityTimer.Tick += (_, _) => PerformTeamsActivity();
        UpdateTimerInterval();
        _activityTimer.Enabled = _teamsMode != TeamsActivityMode.Off;
        _scheduleTimer = new System.Windows.Forms.Timer { Interval = 15_000 };
        _scheduleTimer.Tick += (_, _) => EvaluateSchedule();

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
            ToggleMenuAtCursor();
        };

        ApplyPowerState();
        RebuildMenu();
        _showMenuTimer.Start();
        _scheduleTimer.Start();
        ShowBalloon("Awake & Available is running", ScheduleStatusText);
    }

    private void ToggleMenuAtCursor()
    {
        if (_trayIcon.ContextMenuStrip is not { } menu) return;
        if (menu.Visible)
        {
            menu.Close(ToolStripDropDownCloseReason.CloseCalled);
            return;
        }

        // Clicking the mirrored icon in MacMakeover's top bar first dismisses the
        // native menu, then signals this process. Do not immediately reopen it.
        if (DateTime.UtcNow - _lastMenuClosedUtc < TimeSpan.FromMilliseconds(600)) return;
        menu.Show(Cursor.Position);
    }

    private void RebuildMenu()
    {
        if (_isExiting) return;
        if (_trayIcon.ContextMenuStrip is { Visible: true } visibleMenu)
        {
            _menuRefreshPending = true;
            return;
        }

        _menuRefreshPending = false;
        var menu = new ContextMenuStrip();

        menu.Items.Add(new ToolStripMenuItem(StatusText) { Enabled = false });
        menu.Items.Add(new ToolStripMenuItem(ScheduleStatusText) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());

        var schedule = new ToolStripMenuItem("Automatic schedule · Portugal 09:00–18:00")
        {
            Checked = _settings.ScheduleEnabled
        };
        schedule.ToolTipText = "Uncheck for persistent manual control.";
        schedule.Click += (_, _) => ToggleSchedule();
        menu.Items.Add(schedule);

        if (IsManualOverrideActive)
        {
            var clearOverride = new ToolStripMenuItem("Resume automatic schedule now");
            clearOverride.Click += (_, _) => ClearManualOverride();
            menu.Items.Add(clearOverride);
        }
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
        teamsMenu.DropDownItems.Add(CreateModeItem("Keyboard + mouse pulse (recommended)", TeamsActivityMode.KeyboardAndMousePulse));
        teamsMenu.DropDownItems.Add(CreateModeItem("Mouse-only pulse", TeamsActivityMode.MouseJiggle));
        teamsMenu.DropDownItems.Add(CreateModeItem("Click saved safe point", TeamsActivityMode.SafePointClick));
        menu.Items.Add(teamsMenu);

        var testPulse = new ToolStripMenuItem("Test Teams pulse now");
        testPulse.Click += (_, _) => TestTeamsPulse();
        menu.Items.Add(testPulse);
        if (_lastPulse.HasValue)
        {
            menu.Items.Add(new ToolStripMenuItem(
                $"Last pulse: {_lastPulse.Value:T} ({(_lastPulseAccepted ? "accepted" : "failed")})")
            { Enabled = false });
        }

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

        var closeMenu = new ToolStripMenuItem("Close menu    Esc");
        closeMenu.Click += (_, _) => menu.Close(ToolStripDropDownCloseReason.ItemClicked);
        menu.Items.Add(closeMenu);

        var quit = new ToolStripMenuItem("Quit Awake & Available");
        quit.Click += (_, _) => ExitThread();
        menu.Items.Add(quit);
        menu.Closed += OnMenuClosed;

        var oldMenu = _trayIcon.ContextMenuStrip;
        _trayIcon.ContextMenuStrip = menu;
        if (oldMenu is not null) oldMenu.Closed -= OnMenuClosed;
        oldMenu?.Dispose();
        _trayIcon.Text = StatusText.Length <= 63 ? StatusText : "Awake & Available";
    }

    private void OnMenuClosed(object? sender, ToolStripDropDownClosedEventArgs e)
    {
        _lastMenuClosedUtc = DateTime.UtcNow;

        if (_isExiting)
        {
            _menuRefreshPending = false;
            return;
        }

        if (_menuRefreshPending) RebuildMenu();
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
            TeamsActivityMode.KeyboardAndMousePulse => "Teams input pulse",
            TeamsActivityMode.MouseJiggle => "Teams mouse pulse",
            TeamsActivityMode.SafePointClick => "Teams safe-point click",
            _ => "Teams activity off"
        });

    private bool IsManualOverrideActive =>
        _settings.ScheduleEnabled &&
        _settings.ManualOverrideUntilUtc is { } until &&
        DateTimeOffset.UtcNow < until;

    private string ScheduleStatusText
    {
        get
        {
            if (!_settings.ScheduleEnabled) return "Portugal schedule off · manual controls";
            if (IsManualOverrideActive)
                return $"Manual override until {ScheduleEngine.PortugalTimeLabel(_settings.ManualOverrideUntilUtc!.Value)} Portugal";

            var now = DateTimeOffset.UtcNow;
            return ScheduleEngine.IsWithinWorkHours(now)
                ? $"Portugal schedule active · stops {ScheduleEngine.PortugalTimeLabel(ScheduleEngine.NextBoundaryUtc(now))}"
                : $"Outside Portugal work hours · resumes {ScheduleEngine.PortugalTimeLabel(ScheduleEngine.NextBoundaryUtc(now))}";
        }
    }

    private void TogglePreventSleep()
    {
        _preventSleep = !_preventSleep;
        RegisterManualState();
        ApplyPowerState();
        RebuildMenu();
    }

    private void ToggleSchedule()
    {
        _settings.ScheduleEnabled = !_settings.ScheduleEnabled;
        _settings.ClearManualOverride();

        if (!_settings.ScheduleEnabled)
        {
            _settings.PreventSleep = _preventSleep;
            _settings.TeamsMode = ScheduleEngine.NormalizePersistentMode(_teamsMode);
            _settings.Save();
            RebuildMenu();
            return;
        }

        _settings.Save();
        EvaluateSchedule(forceMenuRefresh: true);
    }

    private void ClearManualOverride()
    {
        _settings.ClearManualOverride();
        _settings.Save();
        EvaluateSchedule(forceMenuRefresh: true);
    }

    private void RegisterManualState()
    {
        _settings.PreventSleep = _preventSleep;
        if (!_settings.ScheduleEnabled)
        {
            _settings.TeamsMode = ScheduleEngine.NormalizePersistentMode(_teamsMode);
            _settings.ClearManualOverride();
        }
        else
        {
            _settings.ManualOverridePreventSleep = _preventSleep;
            _settings.ManualOverrideTeamsMode = ScheduleEngine.NormalizePersistentMode(_teamsMode);
            _settings.ManualOverrideUntilUtc = ScheduleEngine.NextBoundaryUtc(DateTimeOffset.UtcNow);
        }
        _settings.Save();
    }

    private void EvaluateSchedule(bool forceMenuRefresh = false)
    {
        var now = DateTimeOffset.UtcNow;
        var decision = ScheduleEngine.Resolve(_settings, now);
        var settingsChanged = false;
        if (!decision.ManualOverrideActive && _settings.ManualOverrideUntilUtc.HasValue)
        {
            _settings.ClearManualOverride();
            settingsChanged = true;
        }

        var desiredTeamsMode = decision.TeamsMode;
        if (_teamsMode == TeamsActivityMode.SafePointClick &&
            (decision.ManualOverrideActive || !_settings.ScheduleEnabled) &&
            desiredTeamsMode == TeamsActivityMode.KeyboardAndMousePulse)
        {
            // Preserve explicitly armed clicking only for this process. The persisted
            // override remains the safe keyboard/mouse fallback after a restart.
            desiredTeamsMode = TeamsActivityMode.SafePointClick;
        }

        var stateChanged = _preventSleep != decision.PreventSleep || _teamsMode != desiredTeamsMode;
        if (stateChanged)
        {
            _preventSleep = decision.PreventSleep;
            _teamsMode = desiredTeamsMode;
            ApplyPowerState();
            _activityTimer.Enabled = _teamsMode != TeamsActivityMode.Off;
            _pulseFailureNotified = false;
        }

        if (settingsChanged) _settings.Save();
        if (stateChanged || forceMenuRefresh || settingsChanged) RebuildMenu();
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
            RegisterManualState();
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
        // Never silently resume coordinate-based clicking after a restart. The robust
        // keyboard/mouse pulse becomes the persisted fallback for that mode.
        if (mode != TeamsActivityMode.Off)
            _settings.TeamsMode = ScheduleEngine.NormalizePersistentMode(mode);
        RegisterManualState();
        _activityTimer.Enabled = mode != TeamsActivityMode.Off;
        _pulseFailureNotified = false;
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

    private void TestTeamsPulse()
    {
        var before = NativeMethods.GetIdleTime();
        var accepted = PerformTeamsActivity(force: true);
        var after = NativeMethods.GetIdleTime();
        var reset = after < before || after < TimeSpan.FromSeconds(2);
        ShowBalloon(
            accepted && reset ? "Teams pulse verified" : "Teams pulse failed",
            accepted && reset
                ? $"Windows accepted the input and its idle timer reset from {before.TotalSeconds:F1}s to {after.TotalSeconds:F1}s."
                : $"Input accepted: {accepted}. Idle before: {before.TotalSeconds:F1}s; after: {after.TotalSeconds:F1}s.");
    }

    private bool PerformTeamsActivity(bool force = false)
    {
        var mode = _teamsMode;
        if (mode == TeamsActivityMode.Off)
        {
            if (!force) return false;
            mode = TeamsActivityMode.KeyboardAndMousePulse;
        }

        // Do not interfere while the user is actively operating the computer.
        var idleThreshold = TimeSpan.FromSeconds(Math.Max(5, _settings.IntervalSeconds - 5));
        if (!force && NativeMethods.GetIdleTime() < idleThreshold) return true;

        bool accepted;
        if (mode == TeamsActivityMode.KeyboardAndMousePulse)
        {
            accepted = NativeMethods.SendKeyboardAndMousePulse();
            RecordPulse(accepted);
            return accepted;
        }

        if (mode == TeamsActivityMode.MouseJiggle)
        {
            accepted = NativeMethods.SendMousePulse();
            RecordPulse(accepted);
            return accepted;
        }

        if (mode == TeamsActivityMode.SafePointClick)
        {
            if (!_settings.SafePointX.HasValue || !_settings.SafePointY.HasValue)
                return StopTeamsActivityForSafety("No safe click point is saved. Capture a point first.");

            var clickPoint = new Point(_settings.SafePointX.Value, _settings.SafePointY.Value);
            if (!SystemInformation.VirtualScreen.Contains(clickPoint))
                return StopTeamsActivityForSafety(
                    "The saved point is no longer on an active display. Capture it again.");

            var original = Cursor.Position;
            Cursor.Position = clickPoint;
            accepted = NativeMethods.SendLeftClick();
            RecordPulse(accepted);

            var restoreTimer = new System.Windows.Forms.Timer { Interval = 75 };
            restoreTimer.Tick += (_, _) =>
            {
                restoreTimer.Stop();
                restoreTimer.Dispose();
                // Do not drag the pointer away if the user returned during the click.
                if (Cursor.Position == clickPoint) Cursor.Position = original;
            };
            restoreTimer.Start();
            return accepted;
        }

        return StopTeamsActivityForSafety("An unsupported Teams activity mode was disabled.");
    }

    private bool StopTeamsActivityForSafety(string message)
    {
        _teamsMode = TeamsActivityMode.Off;
        _activityTimer.Stop();
        RegisterManualState();
        ShowBalloon("Teams activity stopped", message);
        RebuildMenu();
        return false;
    }

    private void RecordPulse(bool accepted)
    {
        _lastPulse = DateTime.Now;
        _lastPulseAccepted = accepted;
        if (accepted)
        {
            _pulseFailureNotified = false;
        }
        else if (!_pulseFailureNotified)
        {
            _pulseFailureNotified = true;
            ShowBalloon("Teams pulse was blocked",
                "Windows rejected the synthetic input. This can happen when an administrator-level app has focus.");
        }
        RebuildMenu();
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
        _isExiting = true;
        _activityTimer.Stop();
        _scheduleTimer.Stop();
        _showMenuTimer.Stop();
        NativeMethods.SetThreadExecutionState(NativeMethods.ExecutionState.Continuous);
        _trayIcon.Visible = false;

        var menu = _trayIcon.ContextMenuStrip;
        if (menu is not null)
        {
            menu.Closed -= OnMenuClosed;
            _trayIcon.ContextMenuStrip = null;
            menu.Dispose();
        }

        _trayIcon.Dispose();
        _activityTimer.Dispose();
        _scheduleTimer.Dispose();
        _showMenuTimer.Dispose();
        base.ExitThreadCore();
    }
}
