using System.Runtime.InteropServices;

namespace AwakeAndAvailable;

internal static class NativeMethods
{
    [Flags]
    internal enum ExecutionState : uint
    {
        SystemRequired = 0x00000001,
        DisplayRequired = 0x00000002,
        Continuous = 0x80000000
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        internal uint Size;
        internal uint Time;
    }

    internal const uint MouseEventLeftDown = 0x0002;
    internal const uint MouseEventLeftUp = 0x0004;

    [DllImport("kernel32.dll")]
    internal static extern ExecutionState SetThreadExecutionState(ExecutionState state);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [DllImport("user32.dll")]
    internal static extern void mouse_event(uint flags, uint dx, uint dy, uint data, nuint extraInfo);

    internal static TimeSpan GetIdleTime()
    {
        var info = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;

        // LASTINPUTINFO and GetTickCount share the same wrapping 32-bit clock.
        var current = unchecked((uint)Environment.TickCount);
        var elapsed = unchecked(current - info.Time);
        return TimeSpan.FromMilliseconds(elapsed);
    }
}
