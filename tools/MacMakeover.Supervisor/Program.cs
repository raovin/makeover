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
    private static void Main()
    {
        using var singleton = new Mutex(true, @"Local\MacMakeover.Supervisor", out var ownsMutex);
        if (!ownsMutex) return;

        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        Log("Supervisor started.");

        while (true)
        {
            foreach (var component in Components)
            {
                if (IsRunningInCurrentSession(component.ProcessName)) continue;
                StartTask(component);
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

    private static void StartTask(Component component)
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
            process.WaitForExit(5000);
            Log(process.ExitCode == 0
                ? $"Restart requested for {component.ProcessName}."
                : $"Task restart failed for {component.ProcessName}; exit {process.ExitCode}: {process.StandardError.ReadToEnd().Trim()}");
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
