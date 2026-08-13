namespace AwakeAndAvailable;

internal static class ScheduleSelfTest
{
    internal static string Run()
    {
        var tests = new List<string>();

        Check("winter 08:59 inactive",
            !ScheduleEngine.IsWithinWorkHours(Utc(2026, 1, 15, 8, 59), ScheduleEngine.PortugalTimeZone), tests);
        Check("winter 09:00 active",
            ScheduleEngine.IsWithinWorkHours(Utc(2026, 1, 15, 9, 0), ScheduleEngine.PortugalTimeZone), tests);
        Check("winter 18:00 inactive",
            !ScheduleEngine.IsWithinWorkHours(Utc(2026, 1, 15, 18, 0), ScheduleEngine.PortugalTimeZone), tests);

        // Mainland Portugal is UTC+1 in July, so 08:00 UTC is 09:00 local.
        Check("summer 08:59 local inactive",
            !ScheduleEngine.IsWithinWorkHours(Utc(2026, 7, 15, 7, 59), ScheduleEngine.PortugalTimeZone), tests);
        Check("summer 09:00 local active",
            ScheduleEngine.IsWithinWorkHours(Utc(2026, 7, 15, 8, 0), ScheduleEngine.PortugalTimeZone), tests);
        Check("summer 18:00 local inactive",
            !ScheduleEngine.IsWithinWorkHours(Utc(2026, 7, 15, 17, 0), ScheduleEngine.PortugalTimeZone), tests);

        Check("winter next boundary",
            ScheduleEngine.NextBoundaryUtc(Utc(2026, 1, 15, 8, 0), ScheduleEngine.PortugalTimeZone)
                == Utc(2026, 1, 15, 9, 0), tests);
        Check("summer next boundary",
            ScheduleEngine.NextBoundaryUtc(Utc(2026, 7, 15, 7, 0), ScheduleEngine.PortugalTimeZone)
                == Utc(2026, 7, 15, 8, 0), tests);
        Check("after-hours boundary is next day",
            ScheduleEngine.NextBoundaryUtc(Utc(2026, 1, 15, 19, 0), ScheduleEngine.PortugalTimeZone)
                == Utc(2026, 1, 16, 9, 0), tests);

        var settings = new AppSettings
        {
            ScheduleEnabled = true,
            TeamsMode = TeamsActivityMode.KeyboardAndMousePulse
        };
        var active = ScheduleEngine.Resolve(settings, Utc(2026, 1, 15, 12, 0));
        Check("scheduled daytime enables both",
            active.PreventSleep && active.TeamsMode == TeamsActivityMode.KeyboardAndMousePulse, tests);

        var inactive = ScheduleEngine.Resolve(settings, Utc(2026, 1, 15, 20, 0));
        Check("scheduled evening disables both",
            !inactive.PreventSleep && inactive.TeamsMode == TeamsActivityMode.Off, tests);

        settings.ManualOverridePreventSleep = false;
        settings.ManualOverrideTeamsMode = TeamsActivityMode.Off;
        settings.ManualOverrideUntilUtc = Utc(2026, 1, 15, 18, 0);
        var overridden = ScheduleEngine.Resolve(settings, Utc(2026, 1, 15, 12, 0));
        Check("manual override wins before boundary",
            overridden.ManualOverrideActive && !overridden.PreventSleep &&
            overridden.TeamsMode == TeamsActivityMode.Off, tests);

        var expired = ScheduleEngine.Resolve(settings, Utc(2026, 1, 15, 18, 0));
        Check("schedule wins exactly at boundary",
            !expired.ManualOverrideActive && !expired.PreventSleep &&
            expired.TeamsMode == TeamsActivityMode.Off, tests);

        Check("safe click never persists",
            ScheduleEngine.NormalizePersistentMode(TeamsActivityMode.SafePointClick) ==
            TeamsActivityMode.KeyboardAndMousePulse, tests);
        Check("unknown mode becomes safe pulse",
            ScheduleEngine.NormalizePersistentMode((TeamsActivityMode)999) ==
            TeamsActivityMode.KeyboardAndMousePulse, tests);

        var manualSettings = new AppSettings
        {
            ScheduleEnabled = false,
            PreventSleep = true,
            TeamsMode = TeamsActivityMode.MouseJiggle
        };
        var manual = ScheduleEngine.Resolve(manualSettings, Utc(2026, 1, 15, 20, 0));
        Check("disabled schedule preserves manual state",
            manual.PreventSleep && manual.TeamsMode == TeamsActivityMode.MouseJiggle, tests);

        settings.ManualOverrideUntilUtc = Utc(2099, 1, 1, 9, 0);
        var unreasonableOverride = ScheduleEngine.Resolve(settings, Utc(2026, 1, 15, 12, 0));
        Check("unreasonable override expiry is rejected",
            !unreasonableOverride.ManualOverrideActive, tests);

        return $"Passed {tests.Count} schedule tests:{Environment.NewLine}" +
               string.Join(Environment.NewLine, tests.Select(name => $"  ✓ {name}"));
    }

    private static DateTimeOffset Utc(int year, int month, int day, int hour, int minute) =>
        new(year, month, day, hour, minute, 0, TimeSpan.Zero);

    private static void Check(string name, bool condition, ICollection<string> passed)
    {
        if (!condition) throw new InvalidOperationException($"Schedule test failed: {name}");
        passed.Add(name);
    }
}
