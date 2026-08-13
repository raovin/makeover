using System.Threading;

namespace AwakeAndAvailable;

internal static class Program
{
    private const string MutexName = "Local\\AwakeAndAvailable-5A6801C4-296E-4CE7-AB6E-8303BB4EE4D7";
    private const string ShowEventName = "Local\\AwakeAndAvailable.Show-5A6801C4-296E-4CE7-AB6E-8303BB4EE4D7";

    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--schedule-status")
        {
            var now = DateTimeOffset.UtcNow;
            var settings = AppSettings.Load();
            var decision = ScheduleEngine.Resolve(settings, now);
            File.WriteAllText(args[1],
                $"PortugalNow={TimeZoneInfo.ConvertTime(now, ScheduleEngine.PortugalTimeZone):O}{Environment.NewLine}" +
                $"ScheduleEnabled={settings.ScheduleEnabled}{Environment.NewLine}" +
                $"WithinWorkHours={ScheduleEngine.IsWithinWorkHours(now)}{Environment.NewLine}" +
                $"ManualOverrideActive={decision.ManualOverrideActive}{Environment.NewLine}" +
                $"EffectivePreventSleep={decision.PreventSleep}{Environment.NewLine}" +
                $"EffectiveTeamsMode={decision.TeamsMode}{Environment.NewLine}" +
                $"NextBoundaryPortugal={ScheduleEngine.PortugalTimeLabel(decision.NextBoundaryUtc)}{Environment.NewLine}");
            return;
        }

        if (args.Length == 2 && args[0] == "--verify-schedule")
        {
            try
            {
                File.WriteAllText(args[1], ScheduleSelfTest.Run());
            }
            catch (Exception exception)
            {
                File.WriteAllText(args[1], exception.ToString());
                Environment.ExitCode = 3;
            }
            return;
        }

        if (args.Length == 2 && args[0] == "--verify-input")
        {
            Thread.Sleep(1500);
            var before = NativeMethods.GetIdleTime();
            var accepted = NativeMethods.SendKeyboardAndMousePulse();
            Thread.Sleep(150);
            var after = NativeMethods.GetIdleTime();
            File.WriteAllText(args[1],
                $"Accepted={accepted}{Environment.NewLine}" +
                $"IdleBeforeMs={before.TotalMilliseconds:F0}{Environment.NewLine}" +
                $"IdleAfterMs={after.TotalMilliseconds:F0}{Environment.NewLine}");
            Environment.ExitCode = accepted && after < TimeSpan.FromSeconds(2) ? 0 : 2;
            return;
        }

        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var isFirstInstance);
        using var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        if (!isFirstInstance)
        {
            showEvent.Set();
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext(showEvent));
    }
}
