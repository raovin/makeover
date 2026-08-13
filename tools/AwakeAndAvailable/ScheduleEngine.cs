namespace AwakeAndAvailable;

internal readonly record struct ScheduleDecision(
    bool PreventSleep,
    TeamsActivityMode TeamsMode,
    bool ManualOverrideActive,
    DateTimeOffset NextBoundaryUtc);

internal static class ScheduleEngine
{
    internal static readonly TimeSpan StartTime = TimeSpan.FromHours(9);
    internal static readonly TimeSpan EndTime = TimeSpan.FromHours(18);

    internal static TimeZoneInfo PortugalTimeZone { get; } = FindPortugalTimeZone();

    internal static bool IsWithinWorkHours(DateTimeOffset utcNow) =>
        IsWithinWorkHours(utcNow, PortugalTimeZone);

    internal static bool IsWithinWorkHours(DateTimeOffset utcNow, TimeZoneInfo timeZone)
    {
        var localTime = TimeZoneInfo.ConvertTime(utcNow, timeZone).TimeOfDay;
        return localTime >= StartTime && localTime < EndTime;
    }

    internal static DateTimeOffset NextBoundaryUtc(DateTimeOffset utcNow) =>
        NextBoundaryUtc(utcNow, PortugalTimeZone);

    internal static DateTimeOffset NextBoundaryUtc(DateTimeOffset utcNow, TimeZoneInfo timeZone)
    {
        var localNow = TimeZoneInfo.ConvertTime(utcNow, timeZone);
        DateTime localBoundary;
        if (localNow.TimeOfDay < StartTime)
        {
            localBoundary = localNow.Date.Add(StartTime);
        }
        else if (localNow.TimeOfDay < EndTime)
        {
            localBoundary = localNow.Date.Add(EndTime);
        }
        else
        {
            localBoundary = localNow.Date.AddDays(1).Add(StartTime);
        }

        var unspecifiedBoundary = DateTime.SpecifyKind(localBoundary, DateTimeKind.Unspecified);
        return new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(unspecifiedBoundary, timeZone), TimeSpan.Zero);
    }

    internal static ScheduleDecision Resolve(AppSettings settings, DateTimeOffset utcNow)
    {
        var nextBoundary = NextBoundaryUtc(utcNow);
        if (!settings.ScheduleEnabled)
        {
            return new ScheduleDecision(
                settings.PreventSleep,
                NormalizePersistentMode(settings.TeamsMode),
                false,
                nextBoundary);
        }

        var overrideActive =
            settings.ManualOverrideUntilUtc is { } overrideUntil &&
            utcNow < overrideUntil &&
            overrideUntil <= nextBoundary.AddMinutes(1) &&
            settings.ManualOverridePreventSleep.HasValue &&
            settings.ManualOverrideTeamsMode.HasValue;

        if (overrideActive)
        {
            return new ScheduleDecision(
                settings.ManualOverridePreventSleep!.Value,
                NormalizePersistentMode(settings.ManualOverrideTeamsMode!.Value),
                true,
                settings.ManualOverrideUntilUtc!.Value);
        }

        var withinWorkHours = IsWithinWorkHours(utcNow);
        return new ScheduleDecision(
            withinWorkHours,
            withinWorkHours ? NormalizePreferredActiveMode(settings.TeamsMode) : TeamsActivityMode.Off,
            false,
            nextBoundary);
    }

    internal static TeamsActivityMode NormalizePersistentMode(TeamsActivityMode mode) =>
        mode switch
        {
            TeamsActivityMode.Off => TeamsActivityMode.Off,
            TeamsActivityMode.MouseJiggle => TeamsActivityMode.MouseJiggle,
            TeamsActivityMode.KeyboardAndMousePulse => TeamsActivityMode.KeyboardAndMousePulse,
            TeamsActivityMode.SafePointClick => TeamsActivityMode.KeyboardAndMousePulse,
            _ => TeamsActivityMode.KeyboardAndMousePulse
        };

    internal static TeamsActivityMode NormalizePreferredActiveMode(TeamsActivityMode mode) =>
        NormalizePersistentMode(mode) is TeamsActivityMode.Off
            ? TeamsActivityMode.KeyboardAndMousePulse
            : NormalizePersistentMode(mode);

    internal static string PortugalTimeLabel(DateTimeOffset utcTime) =>
        TimeZoneInfo.ConvertTime(utcTime, PortugalTimeZone).ToString("HH:mm");

    private static TimeZoneInfo FindPortugalTimeZone()
    {
        foreach (var id in new[] { "Europe/Lisbon", "GMT Standard Time" })
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(id);
            }
            catch (TimeZoneNotFoundException)
            {
            }
            catch (InvalidTimeZoneException)
            {
            }
        }

        throw new TimeZoneNotFoundException("Neither Europe/Lisbon nor GMT Standard Time is available.");
    }
}
