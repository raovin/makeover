using System.Diagnostics;

namespace MacMakeover.Supervisor;

internal static class Program
{
    private static readonly Component[] Components =
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
            Environment.ExitCode = Components.Length == 4 &&
                                   Components.Select(component => component.TaskName).Distinct().Count() == Components.Length &&
                                   Components.Select(component => component.ProcessName).Distinct().Count() == Components.Length &&
                                   Components.Any(component => component.ProcessName == "MacMakeover.MenuHost") &&
                                   Components.Any(component => component.ProcessName == "MacMakeover.MenuBar") &&
                                   Components.Any(component => component.ProcessName == "MacMakeover.Dock") &&
                                   Components.Any(component => component.ProcessName == "AwakeAndAvailable") &&
                                   !IsRunningInCurrentSession("MacMakeover.Process.That.Does.Not.Exist")
                ? 0
                : 2;
            return;
        }
        using var singleton = new Mutex(true, @"Local\MacMakeover.Supervisor", out var ownsMutex);
        if (!ownsMutex) return;

        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        Log("Supervisor started.");

        while (true)
        {
            foreach (var component in Components)
            {
                if (IsRunningInCurrentSession(component.ProcessName)) continue;
                RequestTaskStart(component);
            }
            Thread.Sleep(TimeSpan.FromSeconds(2));
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

    private static void RequestTaskStart(Component component)
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
                return;
            }
            if (!process.WaitForExit(5000))
            {
                process.Kill(true);
                Log($"Task restart command timed out for {component.ProcessName}.");
                return;
            }
            if (process.ExitCode != 0)
            {
                Log($"Task restart failed for {component.ProcessName}; exit {process.ExitCode}: {process.StandardError.ReadToEnd().Trim()}");
                return;
            }

            var deadline = DateTime.UtcNow.AddSeconds(2);
            while (DateTime.UtcNow < deadline && !IsRunningInCurrentSession(component.ProcessName))
            {
                Thread.Sleep(100);
            }
            Log(IsRunningInCurrentSession(component.ProcessName)
                ? $"Restart verified for {component.ProcessName}."
                : $"Restart request returned success but {component.ProcessName} is still absent; will retry.");
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Log($"Task restart failed for {component.ProcessName}: {exception.Message}");
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

    private sealed record Component(string TaskName, string ProcessName);
}
