using System.Diagnostics;

namespace MacMakeover.Supervisor;

internal static class Program
{
    internal static readonly Component[] Components =
    [
        new("MacMakeover Shell - MenuHost", "MacMakeover.MenuHost"),
        new("MacMakeover Shell - MenuBar", "MacMakeover.MenuBar"),
        new("MacMakeover Shell - Dock", "MacMakeover.Dock"),
        new("MacMakeover Shell - Awake", "AwakeAndAvailable")
    ];

    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MacMakeover", "logs", "supervisor.log");

    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Any(arg => arg.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            Environment.ExitCode = SupervisorSelfTest.Run() ? 0 : 2;
            return;
        }
        using var singleton = new Mutex(true, @"Local\MacMakeover.Supervisor", out var ownsMutex);
        if (!ownsMutex) return;

        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        Log("Supervisor started.");
        var states = Components.ToDictionary(
            component => component.ProcessName,
            _ => new ComponentWatchState(),
            StringComparer.OrdinalIgnoreCase);

        var explorerReady = false;
        var nextExplorerProbeUtc = DateTime.MinValue;
        while (true)
        {
            var now = DateTime.UtcNow;
            if (SupervisorRetryPolicy.ShouldProbeExplorer(now, nextExplorerProbeUtc))
            {
                explorerReady = IsExplorerRunningInCurrentSession();
                nextExplorerProbeUtc = SupervisorRetryPolicy.ScheduleNextExplorerProbeUtc(now);
                if (!explorerReady)
                {
                    Log($"Explorer is not ready in session {Process.GetCurrentProcess().SessionId}; next probe in {SupervisorRetryPolicy.ExplorerProbeDelayMs} ms.");
                }
            }

            // Do not ask schtasks.exe to launch any component until the global
            // Explorer readiness probe has succeeded. While Explorer is absent,
            // the timestamp above bounds process probing to one attempt per 5 seconds.
            if (!explorerReady)
            {
                Thread.Sleep(500);
                continue;
            }

            foreach (var component in Components)
            {
                var state = states[component.ProcessName];
                if (IsRunningInCurrentSession(component.ProcessName))
                {
                    state.Reset();
                    continue;
                }

                // A component can launch immediately once the global Explorer probe
                // succeeds; failed launches still honor their own backoff.
                if (DateTime.UtcNow < state.NextAttemptUtc) continue;

                var outcome = RequestTaskStart(component);
                if (outcome == ComponentLaunchOutcome.Started)
                {
                    state.Reset();
                    continue;
                }

                var retry = SupervisorRetryPolicy.Decide(
                    outcome,
                    explorerReady: true,
                    state.FailureStreak);
                var attemptCompletedUtc = DateTime.UtcNow;
                state.LastOutcome = retry.Outcome;
                state.FailureStreak = Math.Min(state.FailureStreak + 1, SupervisorRetryPolicy.MaxFailureStreak);
                state.NextAttemptUtc = SupervisorRetryPolicy.ScheduleNextAttemptUtc(attemptCompletedUtc, retry.DelayMs);
                Log($"{component.ProcessName} classified as {retry.Outcome}; next launch attempt in {retry.DelayMs} ms (failure streak {state.FailureStreak}).");
            }
            Thread.Sleep(500);
        }
    }

    private static bool IsRunningInCurrentSession(string processName)
    {
        var sessionId = Process.GetCurrentProcess().SessionId;
        foreach (var process in Process.GetProcessesByName(processName))
        {
            using (process)
            {
                try
                {
                    if (process.SessionId == sessionId) return true;
                }
                catch (InvalidOperationException) { }
            }
        }
        return false;
    }

    private static bool IsExplorerRunningInCurrentSession() =>
        IsRunningInCurrentSession("explorer");

    private static ComponentLaunchOutcome RequestTaskStart(Component component)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe"),
                Arguments = $"/Run /TN \"{component.TaskName}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (process is null)
            {
                Log($"Could not start task {component.TaskName}.");
                return ComponentLaunchOutcome.LauncherFailure;
            }
            if (!process.WaitForExit(5000))
            {
                process.Kill(true);
                Log($"Task restart command timed out for {component.ProcessName}.");
                return ComponentLaunchOutcome.LauncherFailure;
            }
            if (process.ExitCode != 0)
            {
                var status = SupervisorRetryPolicy.IsDllInitFailed(process.ExitCode)
                    ? "STATUS_DLL_INIT_FAILED (0xC0000142)"
                    : $"0x{unchecked((uint)process.ExitCode):X8}";
                Log($"Task launcher failure for {component.ProcessName}; exit {process.ExitCode} ({status}): {process.StandardError.ReadToEnd().Trim()}");
                return ComponentLaunchOutcome.LauncherFailure;
            }

            var deadline = DateTime.UtcNow.AddSeconds(2);
            while (DateTime.UtcNow < deadline && !IsRunningInCurrentSession(component.ProcessName))
            {
                Thread.Sleep(100);
            }
            var childRunning = IsRunningInCurrentSession(component.ProcessName);
            Log(childRunning
                ? $"Restart verified for {component.ProcessName}."
                : $"Task launcher returned success but child {component.ProcessName} is still absent; will retry as a child-state failure.");
            return SupervisorRetryPolicy.ClassifyLauncherResult(process.ExitCode, childRunning);
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Log($"Task restart failed for {component.ProcessName}: {exception.Message}");
            return ComponentLaunchOutcome.LauncherFailure;
        }
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    internal sealed record Component(string TaskName, string ProcessName);
}

internal enum ComponentLaunchOutcome
{
    Started,
    LauncherFailure,
    ChildStillAbsent,
    ExplorerNotReady
}

internal readonly record struct RetryDecision(
    ComponentLaunchOutcome Outcome,
    bool ShouldRetry,
    int DelayMs);

internal static class SupervisorRetryPolicy
{
    internal const int InitialBackoffMs = 1000;
    internal const int MaxBackoffMs = 30000;
    internal const int ExplorerProbeDelayMs = 5000;
    internal const int MaxFailureStreak = 6;

    internal static bool ShouldProbeExplorer(DateTime utcNow, DateTime nextProbeUtc) =>
        utcNow >= nextProbeUtc;

    internal static DateTime ScheduleNextExplorerProbeUtc(DateTime utcNow) =>
        utcNow.AddMilliseconds(ExplorerProbeDelayMs);

    internal static DateTime ScheduleNextAttemptUtc(DateTime attemptCompletedUtc, int delayMs) =>
        attemptCompletedUtc.AddMilliseconds(Math.Max(0, delayMs));

    internal static bool IsDllInitFailed(int exitCode) =>
        exitCode == unchecked((int)0xC0000142);

    internal static ComponentLaunchOutcome ClassifyLauncherResult(int launcherExitCode, bool childRunning) =>
        launcherExitCode != 0
            ? ComponentLaunchOutcome.LauncherFailure
            : childRunning
                ? ComponentLaunchOutcome.Started
                : ComponentLaunchOutcome.ChildStillAbsent;

    internal static int NextBackoffMs(int failureStreak)
    {
        var exponent = Math.Clamp(failureStreak, 0, 5);
        return Math.Min(MaxBackoffMs, InitialBackoffMs * (1 << exponent));
    }

    internal static RetryDecision Decide(
        ComponentLaunchOutcome outcome,
        bool explorerReady,
        int failureStreak)
    {
        if (!explorerReady)
        {
            return new RetryDecision(
                ComponentLaunchOutcome.ExplorerNotReady,
                ShouldRetry: false,
                ExplorerProbeDelayMs);
        }

        if (outcome == ComponentLaunchOutcome.Started)
        {
            return new RetryDecision(outcome, ShouldRetry: false, DelayMs: 0);
        }

        return new RetryDecision(
            outcome,
            ShouldRetry: true,
            DelayMs: NextBackoffMs(failureStreak));
    }
}

internal sealed class ComponentWatchState
{
    internal ComponentLaunchOutcome LastOutcome { get; set; } = ComponentLaunchOutcome.Started;
    internal int FailureStreak { get; set; }
    internal DateTime NextAttemptUtc { get; set; } = DateTime.MinValue;

    internal void Reset()
    {
        LastOutcome = ComponentLaunchOutcome.Started;
        FailureStreak = 0;
        NextAttemptUtc = DateTime.MinValue;
    }
}

internal static class SupervisorSelfTest
{
    internal static bool Run()
    {
        var components = Program.Components;
        var taskNames = components.Select(component => component.TaskName).ToArray();
        var processNames = components.Select(component => component.ProcessName).ToArray();
        const int dllInitFailed = unchecked((int)0xC0000142);
        var launcherFailure = SupervisorRetryPolicy.ClassifyLauncherResult(dllInitFailed, childRunning: false);
        var childFailure = SupervisorRetryPolicy.ClassifyLauncherResult(0, childRunning: false);
        var started = SupervisorRetryPolicy.ClassifyLauncherResult(0, childRunning: true);
        var firstRetry = SupervisorRetryPolicy.Decide(launcherFailure, explorerReady: true, failureStreak: 0);
        var secondRetry = SupervisorRetryPolicy.Decide(launcherFailure, explorerReady: true, failureStreak: 1);
        var notReady = SupervisorRetryPolicy.Decide(childFailure, explorerReady: false, failureStreak: 0);
        var probeNow = new DateTime(2026, 8, 13, 12, 0, 0, DateTimeKind.Utc);
        var nextProbeUtc = SupervisorRetryPolicy.ScheduleNextExplorerProbeUtc(probeNow);
        var attemptCompletedUtc = probeNow.AddSeconds(7);
        var nextAttemptUtc = SupervisorRetryPolicy.ScheduleNextAttemptUtc(attemptCompletedUtc, firstRetry.DelayMs);

        return taskNames.Length == 4 &&
               taskNames.Distinct().Count() == taskNames.Length &&
               processNames.Distinct().Count() == processNames.Length &&
               components.Any(component => component.TaskName == "MacMakeover Shell - MenuHost" && component.ProcessName == "MacMakeover.MenuHost") &&
               components.Any(component => component.TaskName == "MacMakeover Shell - MenuBar" && component.ProcessName == "MacMakeover.MenuBar") &&
               components.Any(component => component.TaskName == "MacMakeover Shell - Dock" && component.ProcessName == "MacMakeover.Dock") &&
               components.Any(component => component.TaskName == "MacMakeover Shell - Awake" && component.ProcessName == "AwakeAndAvailable") &&
               !SupervisorRetryPolicy.IsDllInitFailed(0) &&
               SupervisorRetryPolicy.IsDllInitFailed(dllInitFailed) &&
               launcherFailure == ComponentLaunchOutcome.LauncherFailure &&
               childFailure == ComponentLaunchOutcome.ChildStillAbsent &&
               started == ComponentLaunchOutcome.Started &&
               firstRetry.Outcome == ComponentLaunchOutcome.LauncherFailure &&
               firstRetry.ShouldRetry && firstRetry.DelayMs == 1000 &&
               secondRetry.ShouldRetry && secondRetry.DelayMs == 2000 &&
               SupervisorRetryPolicy.NextBackoffMs(99) == SupervisorRetryPolicy.MaxBackoffMs &&
               notReady.Outcome == ComponentLaunchOutcome.ExplorerNotReady &&
               !notReady.ShouldRetry && notReady.DelayMs == SupervisorRetryPolicy.ExplorerProbeDelayMs &&
               !SupervisorRetryPolicy.ShouldProbeExplorer(
                   probeNow.AddMilliseconds(SupervisorRetryPolicy.ExplorerProbeDelayMs - 1),
                   nextProbeUtc) &&
               SupervisorRetryPolicy.ShouldProbeExplorer(nextProbeUtc, nextProbeUtc) &&
               (nextProbeUtc - probeNow).TotalMilliseconds == SupervisorRetryPolicy.ExplorerProbeDelayMs &&
               nextAttemptUtc == attemptCompletedUtc.AddMilliseconds(firstRetry.DelayMs) &&
               nextAttemptUtc > attemptCompletedUtc &&
               !IsRunningInCurrentSessionForTest();
    }

    private static bool IsRunningInCurrentSessionForTest() =>
        Process.GetProcessesByName("MacMakeover.Process.That.Does.Not.Exist").Any();
}
