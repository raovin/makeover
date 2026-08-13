using System.Text.Json;

namespace AwakeAndAvailable;

internal enum TeamsActivityMode
{
    Off = 0,
    MouseJiggle = 1,
    SafePointClick = 2,
    KeyboardAndMousePulse = 3
}

internal sealed class AppSettings
{
    public bool PreventSleep { get; set; } = true;
    public TeamsActivityMode TeamsMode { get; set; } = TeamsActivityMode.KeyboardAndMousePulse;
    public int IntervalSeconds { get; set; } = 30;
    public int? SafePointX { get; set; }
    public int? SafePointY { get; set; }
    public bool ScheduleEnabled { get; set; } = true;
    public DateTimeOffset? ManualOverrideUntilUtc { get; set; }
    public bool? ManualOverridePreventSleep { get; set; }
    public TeamsActivityMode? ManualOverrideTeamsMode { get; set; }

    public static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AwakeAndAvailable", "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath)) ?? new();
                settings.IntervalSeconds = Math.Clamp(settings.IntervalSeconds, 10, 3600);
                settings.TeamsMode = ScheduleEngine.NormalizePersistentMode(settings.TeamsMode);
                if (settings.ManualOverrideTeamsMode.HasValue)
                    settings.ManualOverrideTeamsMode =
                        ScheduleEngine.NormalizePersistentMode(settings.ManualOverrideTeamsMode.Value);

                var overrideIsIncomplete =
                    settings.ManualOverrideUntilUtc.HasValue != settings.ManualOverridePreventSleep.HasValue ||
                    settings.ManualOverrideUntilUtc.HasValue != settings.ManualOverrideTeamsMode.HasValue;
                if (overrideIsIncomplete) settings.ClearManualOverride();
                return settings;
            }
        }
        catch
        {
            // A malformed or inaccessible settings file should not prevent startup.
        }
        return new();
    }

    public void Save()
    {
        var temporaryPath = SettingsPath + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(SettingsPath)!;
            Directory.CreateDirectory(directory);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(temporaryPath, json);
            File.Move(temporaryPath, SettingsPath, overwrite: true);
        }
        catch (Exception exception)
        {
            System.Diagnostics.Debug.WriteLine($"Could not save Awake & Available settings: {exception}");
            try
            {
                if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
            }
            catch
            {
                // Preserve app availability even if cleanup is also blocked.
            }
        }
    }

    public void ClearManualOverride()
    {
        ManualOverrideUntilUtc = null;
        ManualOverridePreventSleep = null;
        ManualOverrideTeamsMode = null;
    }
}
