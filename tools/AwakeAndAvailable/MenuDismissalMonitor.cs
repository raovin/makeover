using System.Runtime.InteropServices;

namespace AwakeAndAvailable;

internal sealed class MenuDismissalMonitor : IDisposable
{
    private const int WhMouseLl = 14;
    private const uint WmLeftButtonDown = 0x0201;
    private const uint WmRightButtonDown = 0x0204;
    private const uint WmMiddleButtonDown = 0x0207;
    private const uint WmXButtonDown = 0x020B;

    private readonly Action<Point> _mouseDown;
    private readonly HookProcedure _hookProcedure;
    private nint _hook;

    internal MenuDismissalMonitor(Action<Point> mouseDown)
    {
        _mouseDown = mouseDown;
        _hookProcedure = OnMouseHook;
    }

    internal bool Start()
    {
        if (_hook != 0) return true;
        _hook = SetWindowsHookEx(WhMouseLl, _hookProcedure, GetModuleHandle(null), 0);
        return _hook != 0;
    }

    internal void Stop()
    {
        if (_hook == 0) return;
        UnhookWindowsHookEx(_hook);
        _hook = 0;
    }

    private nint OnMouseHook(int code, nuint message, nint data)
    {
        if (code >= 0 && IsMouseDownMessage((uint)message))
        {
            var details = Marshal.PtrToStructure<LowLevelMouseHookData>(data);
            _mouseDown(new Point(details.Point.X, details.Point.Y));
        }

        return CallNextHookEx(_hook, code, message, data);
    }

    private static bool IsMouseDownMessage(uint message) =>
        message is WmLeftButtonDown or WmRightButtonDown or WmMiddleButtonDown or WmXButtonDown;

    public void Dispose()
    {
        Stop();
        GC.SuppressFinalize(this);
    }

    private delegate nint HookProcedure(int code, nuint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LowLevelMouseHookData
    {
        internal NativePoint Point;
        internal uint MouseData;
        internal uint Flags;
        internal uint Time;
        internal nuint ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int hookId, HookProcedure callback, nint module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nuint message, nint data);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? moduleName);
}
