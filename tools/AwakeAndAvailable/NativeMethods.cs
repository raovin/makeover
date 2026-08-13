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

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        internal uint Type;
        internal InputUnion Data;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] internal MouseInput Mouse;
        [FieldOffset(0)] internal KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        internal int X;
        internal int Y;
        internal uint MouseData;
        internal uint Flags;
        internal uint Time;
        internal nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        internal ushort VirtualKey;
        internal ushort ScanCode;
        internal uint Flags;
        internal uint Time;
        internal nuint ExtraInfo;
    }

    private const uint InputMouse = 0;
    private const uint InputKeyboard = 1;
    private const uint MouseMove = 0x0001;
    private const uint MouseLeftDown = 0x0002;
    private const uint MouseLeftUp = 0x0004;
    private const uint KeyUp = 0x0002;
    private const ushort VirtualKeyF15 = 0x7E;

    [DllImport("kernel32.dll")]
    internal static extern ExecutionState SetThreadExecutionState(ExecutionState state);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, [In] Input[] inputs, int inputSize);

    internal static bool SendKeyboardAndMousePulse()
    {
        var inputs = new[]
        {
            Keyboard(VirtualKeyF15, 0),
            Keyboard(VirtualKeyF15, KeyUp),
            Mouse(1, 0, MouseMove),
            Mouse(-1, 0, MouseMove)
        };
        return Send(inputs);
    }

    internal static bool SendMousePulse()
    {
        var inputs = new[]
        {
            Mouse(1, 0, MouseMove),
            Mouse(-1, 0, MouseMove)
        };
        return Send(inputs);
    }

    internal static bool SendLeftClick()
    {
        var inputs = new[]
        {
            Mouse(0, 0, MouseLeftDown),
            Mouse(0, 0, MouseLeftUp)
        };
        return Send(inputs);
    }

    private static Input Mouse(int x, int y, uint flags) => new()
    {
        Type = InputMouse,
        Data = new InputUnion
        {
            Mouse = new MouseInput { X = x, Y = y, Flags = flags }
        }
    };

    private static Input Keyboard(ushort virtualKey, uint flags) => new()
    {
        Type = InputKeyboard,
        Data = new InputUnion
        {
            Keyboard = new KeyboardInput { VirtualKey = virtualKey, Flags = flags }
        }
    };

    private static bool Send(Input[] inputs) =>
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) == inputs.Length;

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
