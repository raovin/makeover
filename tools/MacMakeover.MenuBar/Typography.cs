using System.Drawing.Text;

namespace MacMakeover.MenuBar;

internal sealed class Typography : IDisposable
{
    private readonly List<PrivateFontCollection> _collections = [];

    public Typography()
    {
        Text = LoadFace("Manrope-Regular.ttf", "Segoe UI", 8.65F);
        Emphasis = LoadFace("Manrope-SemiBold.ttf", "Segoe UI Semibold", 9F);
        Telemetry = LoadFace("JetBrainsMono-Medium.ttf", "Cascadia Mono", 7.65F);
        Icon = new Font("Segoe Fluent Icons", 9.5F, FontStyle.Regular, GraphicsUnit.Point);
    }

    public Font Text { get; }
    public Font Emphasis { get; }
    public Font Telemetry { get; }
    public Font Icon { get; }

    private Font LoadFace(string fileName, string fallbackFamily, float size)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Fonts", fileName);
        if (File.Exists(path))
        {
            try
            {
                var collection = new PrivateFontCollection();
                collection.AddFontFile(path);
                if (collection.Families.Length > 0)
                {
                    _collections.Add(collection);
                    return new Font(collection.Families[0], size, FontStyle.Regular, GraphicsUnit.Point);
                }
                collection.Dispose();
            }
            catch (ArgumentException)
            {
                // A corrupt optional asset must not prevent the shell from starting.
            }
        }

        return new Font(fallbackFamily, size, FontStyle.Regular, GraphicsUnit.Point);
    }

    public void Dispose()
    {
        Text.Dispose();
        Emphasis.Dispose();
        Telemetry.Dispose();
        Icon.Dispose();
        foreach (var collection in _collections) collection.Dispose();
    }
}
