namespace AwakeAndAvailable;

internal static class TrayIconState
{
    internal static string CurrentIconPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AwakeAndAvailable",
        "current-tray.ico");

    internal static void Publish(Icon icon)
    {
        using var stream = new MemoryStream();
        icon.Save(stream);
        var currentBytes = stream.ToArray();
        var path = CurrentIconPath;

        if (File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(currentBytes)) return;

        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $"current-tray-{Environment.ProcessId}.tmp");
        File.WriteAllBytes(temporaryPath, currentBytes);
        File.Move(temporaryPath, path, overwrite: true);
    }
}
