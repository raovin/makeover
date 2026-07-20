using System.Runtime.InteropServices;
using System.Text;

namespace MacMakeover.Dock;

internal static class NativeMethods
{
    public const int WsExToolWindow = 0x80;
    public const int WsExTransparent = 0x20;
    public const int WsExLayered = 0x80000;
    public const int WsExNoActivate = 0x08000000;
    public const int AbmNew = 0;
    public const int AbmRemove = 1;
    public const int AbmQueryPos = 2;
    public const int AbmSetPos = 3;
    public const int AbnPosChanged = 1;
    public const int AbeBottom = 3;
    public const int SwHide = 0;
    public const int SwShow = 5;
    public const int SwRestore = 9;
    public static readonly IntPtr HwndTopMost = new(-1);
    public static readonly IntPtr DpiAwarenessContextPerMonitorAwareV2 = new(-4);
    public const uint SwpNoActivate = 0x0010;
    public const uint SwpShowWindow = 0x0040;
    public const uint ShgfiIcon = 0x100;
    public const uint ShgfiLargeIcon = 0;

    [Flags]
    public enum ShellImageFlags : uint { ResizeToFit = 0, BiggerSizeOk = 1, IconOnly = 4 }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage(Size size, ShellImageFlags flags, out IntPtr bitmap);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AppBarData { public int Size; public IntPtr Window; public uint CallbackMessage; public uint Edge; public Rect Bounds; public IntPtr Parameter; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct NativePoint { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ShFileInfo { public IntPtr Icon; public int IconIndex; public uint Attributes; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName; }

    public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint message, ref AppBarData data);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SHGetFileInfo(string path, uint attributes, out ShFileInfo info, uint size, uint flags);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)] public static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext, ref Guid interfaceId, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder className, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string message);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr handle);
}
