namespace MacMakeover.MenuBar;

internal sealed class Typography : IDisposable
{
    public Typography(float opticalScale = 1F)
    {
        // The native Windows variable text faces remain sharply hinted at 96 DPI,
        // where privately loaded display fonts looked uneven on external monitors.
        Text = new Font("Segoe UI Variable Text", 8.7F * opticalScale, FontStyle.Regular, GraphicsUnit.Point);
        Emphasis = new Font("Segoe UI Variable Text Semibold", 8.9F * opticalScale, FontStyle.Regular, GraphicsUnit.Point);
        Telemetry = new Font("Segoe UI Variable Text", 8.1F * opticalScale, FontStyle.Regular, GraphicsUnit.Point);
        Icon = new Font("Segoe Fluent Icons", 9.5F * opticalScale, FontStyle.Regular, GraphicsUnit.Point);
    }

    public Font Text { get; }
    public Font Emphasis { get; }
    public Font Telemetry { get; }
    public Font Icon { get; }

    public void Dispose()
    {
        Text.Dispose();
        Emphasis.Dispose();
        Telemetry.Dispose();
        Icon.Dispose();
    }
}
