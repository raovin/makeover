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
        if (args.Any(arg => arg.Equals("--lifecycle-helper", StringComparison.OrdinalIgnoreCase)))
        {
            // A bounded, harmless child used only by --self-test. It never enters
            // the mutex/watchdog path or starts a scheduled task.
            Thread.Sleep(1500);
            return;
        }
        if (args.Any(arg => arg.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            Environment.ExitCode = SupervisorSelfTest.Run() ? 0 : 2;
            return;
        }
        using var singleton = new Mutex(true, @"Local\MacMakeover.Supervisor", out var ownsMutex);
        if (!ownsMutex) return;

        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        Log("Supervisor started.");
        var sessionId = Process.GetCurrentProcess().SessionId;
        using var explorerObserver = new ProcessLifetimeObserver("explorer", sessionId);
        var states = Components.ToDictionary(
            component => component.ProcessName,
            component => new ComponentWatchState(component.ProcessName, sessionId),
            StringComparer.OrdinalIgnoreCase);

        try
        {
            // The initial reconciliation is the only process enumeration performed
            // for a healthy component. Each observer then retains the process
            // lifetime event handle and updates its state when the process exits.
            explorerObserver.Refresh();
            foreach (var state in states.Values) state.Observer.Refresh();

            var explorerReady = IsExplorerRunningInCurrentSession(explorerObserver);
            var nextExplorerProbeUtc = SupervisorRetryPolicy.ScheduleNextExplorerProbeUtc(DateTime.UtcNow);
            while (true)
            {
                var now = DateTime.UtcNow;
                if (SupervisorRetryPolicy.ShouldProbeExplorer(now, nextExplorerProbeUtc) &&
                    !explorerObserver.IsRunning)
                {
                    explorerObserver.Refresh();
                    explorerReady = IsExplorerRunningInCurrentSession(explorerObserver);
                    nextExplorerProbeUtc = SupervisorRetryPolicy.ScheduleNextExplorerProbeUtc(now);
                    if (!explorerReady)
                    {
                        Log($"Explorer is not ready in session {Process.GetCurrentProcess().SessionId}; next probe in {SupervisorRetryPolicy.ExplorerProbeDelayMs} ms.");
                    }
                }
                else if (!explorerObserver.IsRunning)
                {
                    // An exit notification can invalidate readiness before the next
                    // scheduled Explorer reconciliation.
                    explorerReady = false;
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
                    state.ReconcileIfMissing(now);
                    if (state.Observer.IsRunning)
                    {
                        state.Reset();
                        continue;
                    }

                    // A component can launch immediately once the global Explorer probe
                    // succeeds; failed launches still honor their own backoff.
                    if (DateTime.UtcNow < state.NextAttemptUtc) continue;

                    var outcome = RequestTaskStart(component, state.Observer);
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
                    state.NextObservationUtc = SupervisorRetryPolicy.ScheduleNextObservationUtc(attemptCompletedUtc);
                    Log($"{component.ProcessName} classified as {retry.Outcome}; next launch attempt in {retry.DelayMs} ms (failure streak {state.FailureStreak}).");
                }
                Thread.Sleep(500);
            }
        }
        finally
        {
            foreach (var state in states.Values) state.Observer.Dispose();
        }
    }

    private static bool IsExplorerRunningInCurrentSession(ProcessLifetimeObserver observer) =>
        observer.IsRunning;

    private static ComponentLaunchOutcome RequestTaskStart(
        Component component,
        ProcessLifetimeObserver observer)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe"),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = false,
                RedirectStandardError = true
            };
            startInfo.ArgumentList.Add("/Run");
            startInfo.ArgumentList.Add("/TN");
            startInfo.ArgumentList.Add(component.TaskName);
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                Log($"Could not start task {component.TaskName}.");
                return ComponentLaunchOutcome.LauncherFailure;
            }

            // Keep stderr draining while schtasks runs so an unexpectedly verbose
            // launcher cannot fill the redirected pipe and appear to hang.
            var standardError = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(5000))
            {
                try
                {
                    process.Kill(true);
                    process.WaitForExit(1000);
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception) { }
                Log($"Task restart command timed out for {component.ProcessName}.");
                return ComponentLaunchOutcome.LauncherFailure;
            }
            if (process.ExitCode != 0)
            {
                var status = SupervisorRetryPolicy.IsDllInitFailed(process.ExitCode)
                    ? "STATUS_DLL_INIT_FAILED (0xC0000142)"
                    : $"0x{unchecked((uint)process.ExitCode):X8}";
                Log($"Task launcher failure for {component.ProcessName}; exit {process.ExitCode} ({status}): {standardError.GetAwaiter().GetResult().Trim()}");
                return ComponentLaunchOutcome.LauncherFailure;
            }

            var childRunning = observer.WaitForRunning(2000);
            Log(childRunning
                ? $"Restart verified for {component.ProcessName}."
                : $"Task launcher returned success but child {component.ProcessName} is still absent; will retry as a child-state failure.");
            return SupervisorRetryPolicy.ClassifyLauncherResult(process.ExitCode, childRunning);
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
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
    internal const int MissingProcessProbeDelayMs = 1000;
    internal const int MaxFailureStreak = 6;

    internal static bool ShouldProbeExplorer(DateTime utcNow, DateTime nextProbeUtc) =>
        utcNow >= nextProbeUtc;

    internal static DateTime ScheduleNextExplorerProbeUtc(DateTime utcNow) =>
        utcNow.AddMilliseconds(ExplorerProbeDelayMs);

    internal static DateTime ScheduleNextAttemptUtc(DateTime attemptCompletedUtc, int delayMs) =>
        attemptCompletedUtc.AddMilliseconds(Math.Max(0, delayMs));

    internal static DateTime ScheduleNextObservationUtc(DateTime observationCompletedUtc) =>
        observationCompletedUtc.AddMilliseconds(MissingProcessProbeDelayMs);

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
    internal ComponentWatchState(string processName, int sessionId)
    {
        Observer = new ProcessLifetimeObserver(processName, sessionId);
    }

    internal ProcessLifetimeObserver Observer { get; }
    internal ComponentLaunchOutcome LastOutcome { get; set; } = ComponentLaunchOutcome.Started;
    internal int FailureStreak { get; set; }
    internal DateTime NextAttemptUtc { get; set; } = DateTime.MinValue;
    internal DateTime NextObservationUtc { get; set; } = DateTime.MinValue;

    internal void ReconcileIfMissing(DateTime utcNow)
    {
        if (Observer.IsRunning || utcNow < NextObservationUtc) return;
        Observer.Refresh();
        NextObservationUtc = SupervisorRetryPolicy.ScheduleNextObservationUtc(utcNow);
    }

    internal void Reset()
    {
        LastOutcome = ComponentLaunchOutcome.Started;
        FailureStreak = 0;
        NextAttemptUtc = DateTime.MinValue;
        NextObservationUtc = DateTime.MinValue;
    }
}

internal sealed class ProcessLifetimeObserver : IDisposable
{
    private readonly string _processName;
    private readonly int _sessionId;
    private readonly Func<string, Process[]> _enumerateProcesses;
    private readonly Func<Process, bool> _isExited;
    private readonly Action<Process>? _beforeEventRegistration;
    private readonly object _gate = new();
    private readonly Dictionary<int, TrackedProcess> _tracked = new();
    private int _runningCount;
    private bool _disposed;

    internal ProcessLifetimeObserver(
        string processName,
        int sessionId,
        Func<string, Process[]>? enumerateProcesses = null,
        Func<Process, bool>? isExited = null,
        Action<Process>? beforeEventRegistration = null)
    {
        _processName = processName;
        _sessionId = sessionId;
        _enumerateProcesses = enumerateProcesses ?? (name => Process.GetProcessesByName(name));
        _isExited = isExited ?? (process => process.HasExited);
        _beforeEventRegistration = beforeEventRegistration;
    }

    internal bool IsRunning => Volatile.Read(ref _runningCount) > 0;

    internal int ActiveCount => Math.Max(0, Volatile.Read(ref _runningCount));

    internal void Refresh()
    {
        Process[] processes;
        try
        {
            processes = _enumerateProcesses(_processName);
        }
        catch (InvalidOperationException)
        {
            return;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return;
        }

        foreach (var process in processes)
        {
            var keep = false;
            try
            {
                if (process.SessionId == _sessionId) keep = TryTrack(process);
            }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
            finally
            {
                if (!keep) process.Dispose();
            }
        }

        PruneExited();
    }

    internal bool WaitForRunning(int timeoutMs)
    {
        var timeout = Math.Max(0, timeoutMs);
        var deadline = Stopwatch.GetTimestamp() +
            (long)(timeout / 1000.0 * Stopwatch.Frequency);
        do
        {
            if (IsRunning) return true;
            Refresh();
            if (IsRunning) return true;
            if (Stopwatch.GetTimestamp() >= deadline) break;
            Thread.Sleep(Math.Min(100, Math.Max(1, timeout)));
        } while (Stopwatch.GetTimestamp() < deadline);

        return IsRunning;
    }

    private bool TryTrack(Process process)
    {
        int processId;
        try { processId = process.Id; }
        catch (InvalidOperationException) { return false; }
        catch (System.ComponentModel.Win32Exception) { return false; }

        List<TrackedProcess>? releases = null;
        TrackedProcess? attempted = null;
        TrackedProcess? inlineExited = null;
        var result = false;
        lock (_gate)
        {
            if (_disposed) return false;

            if (_tracked.TryGetValue(processId, out var existing))
            {
                var existingExited = false;
                try { existingExited = _isExited(existing.Process); }
                catch (InvalidOperationException) { existingExited = true; }
                catch (System.ComponentModel.Win32Exception) { existingExited = true; }
                if (!existingExited && Volatile.Read(ref existing.Active) == 1) return false;
                var existingRelease = RemoveTrackedLocked(existing);
                if (existingRelease is not null) (releases ??= new()).Add(existingRelease);
            }

            try
            {
                if (!_isExited(process))
                {
                    var tracked = new TrackedProcess(process, processId);
                    attempted = tracked;
                    tracked.ExitedHandler = (_, _) => HandleExited(tracked);
                    _tracked.Add(processId, tracked);
                    // Ownership transfers to the observer at the dictionary
                    // insertion.  Any later setup failure is cleaned up by
                    // Release, so Refresh must not dispose this instance too.
                    result = true;
                    Interlocked.Increment(ref _runningCount);
                    _beforeEventRegistration?.Invoke(process);
                    process.Exited += tracked.ExitedHandler!;
                    tracked.EventRegistered = true;
                    process.EnableRaisingEvents = true;
                    if (_isExited(process)) inlineExited = tracked;
                }
            }
            catch (InvalidOperationException)
            {
                if (attempted is not null)
                {
                    var failedRelease = RemoveTrackedLocked(attempted);
                    if (failedRelease is not null) (releases ??= new()).Add(failedRelease);
                }
            }
            catch (System.ComponentModel.Win32Exception)
            {
                if (attempted is not null)
                {
                    var failedRelease = RemoveTrackedLocked(attempted);
                    if (failedRelease is not null) (releases ??= new()).Add(failedRelease);
                }
            }
        }

        if (releases is not null)
        {
            foreach (var release in releases) Release(release);
        }
        if (inlineExited is not null) HandleExited(inlineExited);
        // The observer owns the Process instance once it has been added, even
        // when it exits between EnableRaisingEvents and this return.  Returning
        // true in that case prevents Refresh from disposing the same handle a
        // second time; HandleExited/Release performs the one ownership release.
        return result;
    }

    private void HandleExited(TrackedProcess tracked)
    {
        TrackedProcess? release = null;
        lock (_gate)
        {
            if (_tracked.TryGetValue(tracked.ProcessId, out var current) &&
                ReferenceEquals(current, tracked))
            {
                release = RemoveTrackedLocked(tracked);
            }
        }
        if (release is not null) Release(release);
    }

    private void PruneExited()
    {
        TrackedProcess[] snapshot;
        lock (_gate) snapshot = _tracked.Values.ToArray();
        foreach (var tracked in snapshot)
        {
            var exited = false;
            try { exited = _isExited(tracked.Process); }
            catch (InvalidOperationException) { exited = true; }
            catch (System.ComponentModel.Win32Exception) { exited = true; }
            if (!exited) continue;
            HandleExited(tracked);
        }
    }

    private TrackedProcess? RemoveTrackedLocked(TrackedProcess tracked)
    {
        if (!_tracked.TryGetValue(tracked.ProcessId, out var current) ||
            !ReferenceEquals(current, tracked)) return null;
        _tracked.Remove(tracked.ProcessId);
        if (Interlocked.Exchange(ref tracked.Active, 0) == 1)
        {
            Interlocked.Decrement(ref _runningCount);
        }
        return tracked;
    }

    private static void Release(TrackedProcess tracked)
    {
        if (Interlocked.Exchange(ref tracked.Released, 1) != 0) return;
        if (tracked.EventRegistered && tracked.ExitedHandler is not null)
        {
            try { tracked.Process.Exited -= tracked.ExitedHandler; }
            catch (InvalidOperationException) { }
        }
        try { tracked.Process.Dispose(); }
        catch (ObjectDisposedException) { }
        catch (InvalidOperationException) { }
    }

    public void Dispose()
    {
        TrackedProcess[] releases;
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            releases = _tracked.Values.ToArray();
            foreach (var tracked in releases) RemoveTrackedLocked(tracked);
            _tracked.Clear();
            Interlocked.Exchange(ref _runningCount, 0);
        }
        foreach (var tracked in releases) Release(tracked);
    }

    private sealed class TrackedProcess
    {
        internal TrackedProcess(Process process, int processId)
        {
            Process = process;
            ProcessId = processId;
        }

        internal Process Process { get; }
        internal int ProcessId { get; }
        internal EventHandler? ExitedHandler { get; set; }
        internal bool EventRegistered { get; set; }
        internal int Active = 1;
        internal int Released;
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
        var nextObservationUtc = SupervisorRetryPolicy.ScheduleNextObservationUtc(attemptCompletedUtc);
        using var missingObserver = new ProcessLifetimeObserver(
            "MacMakeover.Process.That.Does.Not.Exist",
            Process.GetCurrentProcess().SessionId);
        missingObserver.Refresh();
        var lifecycle = RunProcessLifetimeSelfTest();
        var registrationFailure = RunProcessRegistrationFailureSelfTest();

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
                nextObservationUtc == attemptCompletedUtc.AddMilliseconds(SupervisorRetryPolicy.MissingProcessProbeDelayMs) &&
                !missingObserver.IsRunning &&
                lifecycle &&
                registrationFailure;
    }

    private static bool RunProcessRegistrationFailureSelfTest()
    {
        var current = Process.GetCurrentProcess();
        Process? initiallyTracked = null;
        var forceNextExistingExit = false;
        var registrationAttempts = 0;
        using var observer = new ProcessLifetimeObserver(
            current.ProcessName,
            current.SessionId,
            enumerateProcesses: _ => [Process.GetProcessById(current.Id)],
            isExited: process =>
            {
                initiallyTracked ??= process;
                if (forceNextExistingExit && ReferenceEquals(process, initiallyTracked))
                {
                    forceNextExistingExit = false;
                    return true;
                }
                return process.HasExited;
            },
            beforeEventRegistration: _ =>
            {
                if (Interlocked.Increment(ref registrationAttempts) == 2)
                {
                    throw new InvalidOperationException("Injected registration failure for self-test.");
                }
            });

        observer.Refresh();
        if (observer.ActiveCount != 1 || initiallyTracked is null)
        {
            return false;
        }

        // The next enumeration returns a new Process wrapper for the same PID.
        // Pretend the old handle observed an exit, then fail registration after
        // the replacement has entered the observer ledger. The observer must
        // release both wrappers and leave no active count behind.
        forceNextExistingExit = true;
        observer.Refresh();
        return registrationAttempts == 2 && observer.ActiveCount == 0 && !observer.IsRunning;
    }

    private static bool RunProcessLifetimeSelfTest()
    {
        var current = Process.GetCurrentProcess();
        var executable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executable)) return false;

        using var observer = new ProcessLifetimeObserver(current.ProcessName, current.SessionId);
        observer.Refresh();
        var baseline = observer.ActiveCount;
        var children = new List<Process>();
        try
        {
            for (var index = 0; index < 2; index++)
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = executable,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                startInfo.ArgumentList.Add("--lifecycle-helper");
                var child = Process.Start(startInfo);
                if (child is null) return false;
                children.Add(child);
            }

            var startDeadline = DateTime.UtcNow.AddSeconds(5);
            var sawMultiple = false;
            while (DateTime.UtcNow < startDeadline)
            {
                observer.Refresh();
                if (observer.ActiveCount >= baseline + children.Count)
                {
                    sawMultiple = true;
                    break;
                }
                Thread.Sleep(50);
            }

            foreach (var child in children)
            {
                if (!child.WaitForExit(5000))
                {
                    try { child.Kill(true); } catch (InvalidOperationException) { }
                    child.WaitForExit(1000);
                }
            }

            var cleanupDeadline = DateTime.UtcNow.AddSeconds(5);
            while (DateTime.UtcNow < cleanupDeadline)
            {
                observer.Refresh();
                if (observer.ActiveCount <= baseline) break;
                Thread.Sleep(50);
            }

            var cleaned = observer.ActiveCount == baseline;
            return sawMultiple && cleaned;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
        finally
        {
            foreach (var child in children)
            {
                try
                {
                    if (!child.HasExited) child.Kill(true);
                    child.WaitForExit(1000);
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception) { }
                child.Dispose();
            }
        }
    }
}
