using System.Text.Json;

namespace AwakeAndAvailable;

internal enum TeamsActivityMode
{
    Off,
    MouseJiggle,
    SafePointClick
}

internal sealed class AppSettings
{
    public bool PreventSleep { get; set; } = true;
    public int IntervalSeconds { get; set; } = 60;
    public int? SafePointX { get; set; }
    public int? SafePointY { get; set; }

    public static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AwakeAndAvailable", "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath)) ?? new();
        }
        catch
        {
            // A malformed or inaccessible settings file should not prevent startup.
        }
        return new();
    }

    public void Save()
    {
        var directory = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(directory);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }
}
