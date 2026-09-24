using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MacMakeover.MenuBar;

internal static class NativeMethods
{
    public const int WsExToolWindow = 0x00000080;
    public const int WsExNoActivate = 0x08000000;
    public const int WmAppCommand = 0x0319;
    public const int WmContextMenu = 0x007B;
    private const int WmUser = 0x0400;
    // tailscale/walk allocates its first WalkNotifyIconSink message at
    // WM_USER + 3. This is used only after the live window class and owner
    // process have both been verified; failure is always a no-op.
    private const int WalkNotifyIconMessage = WmUser + 3;
    public const int AppCommandVolumeUp = 10;
    public const int AppCommandVolumeDown = 9;
    public const int SwRestore = 9;
    public const int SwpNoMove = 0x0002;
    public const int SwpNoSize = 0x0001;
    public const int SwpNoActivate = 0x0010;
    public const int SwpShowWindow = 0x0040;
    public static readonly IntPtr HwndTopMost = new(-1);
    public const int AbmNew = 0;
    public const int AbmRemove = 1;
    public const int AbmQueryPos = 2;
    public const int AbmSetPos = 3;
    public const int AbnPosChanged = 1;
    public const int AbeTop = 1;

    [StructLayout(LayoutKind.Sequential)]
    public struct AppBarData
    {
        public int Size;
        public IntPtr Window;
        public uint CallbackMessage;
        public uint Edge;
        public Rect Bounds;
        public IntPtr Parameter;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public readonly Rectangle ToRectangle() => Rectangle.FromLTRB(Left, Top, Right, Bottom);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NotifyIconIdentifier
    {
        public uint Size;
        public IntPtr Window;
        public uint Id;
        public Guid IconGuid;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct FileTime
    {
        public uint Low;
        public uint High;
        public readonly ulong ToUInt64() => ((ulong)High << 32) | Low;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public sealed class MemoryStatusEx
    {
        public uint Length = (uint)Marshal.SizeOf<MemoryStatusEx>();
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [DllImport("shell32.dll")]
    public static extern UIntPtr SHAppBarMessage(uint message, ref AppBarData data);

    [DllImport("shell32.dll")]
    private static extern int Shell_NotifyIconGetRect(
        ref NotifyIconIdentifier identifier,
        out Rect iconRect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern uint RegisterWindowMessage(string message);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsIconic(IntPtr window);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindWindowEx(
        IntPtr parent,
        IntPtr after,
        string? className,
        string? windowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        int flags);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int key);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatusEx buffer);

    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern int GetBestInterface(uint destinationAddress, out uint bestInterfaceIndex);

    [DllImport("powrprof.dll")]
    public static extern uint PowerGetUserConfiguredACPowerMode(out Guid powerMode);

    [DllImport("powrprof.dll")]
    public static extern uint PowerGetUserConfiguredDCPowerMode(out Guid powerMode);

    [DllImport("powrprof.dll")]
    public static extern uint PowerGetEffectiveOverlayScheme(out Guid powerMode);

    internal static bool TryShowNotificationIconContextMenu(
        Guid iconGuid,
        string executablePath,
        int anchorX,
        int anchorY)
    {
        if (iconGuid == Guid.Empty || string.IsNullOrWhiteSpace(executablePath)) return false;
        if (!IsNotificationIconLive(iconGuid)) return false;
        var virtualScreen = SystemInformation.VirtualScreen;
        if (!virtualScreen.Contains(anchorX, anchorY)) return false;
        var anchor = new Point { X = anchorX, Y = anchorY };

        // Walk-based tray clients own a hidden sink window and handle their
        // native context menu on the shell callback message. This path keeps
        // working while the Explorer taskbar is intentionally hidden by the
        // custom dock.
        if (TryShowWalkContextMenu(executablePath, anchor)) return true;

        // There is no supported generic shell API for asking another process
        // to open its tray menu. Do not synthesize a global mouse click: the
        // custom dock hides Explorer's notification area and a stale shell
        // rectangle must never be treated as a safe target.
        return false;
    }

    internal static bool IsNotificationIconLive(Guid iconGuid)
    {
        if (iconGuid == Guid.Empty) return false;
        var identifier = new NotifyIconIdentifier
        {
            Size = (uint)Marshal.SizeOf<NotifyIconIdentifier>(),
            IconGuid = iconGuid
        };
        return Shell_NotifyIconGetRect(ref identifier, out _) >= 0;
    }

    internal static bool IsKnownWalkTrayClient(string executablePath) =>
        Path.GetFileName(executablePath).Equals("tailscale-ipn.exe", StringComparison.OrdinalIgnoreCase);

    internal static bool ShouldDispatchWalkContextMenu(string executablePath, int matchingSinkCount) =>
        IsKnownWalkTrayClient(executablePath) && matchingSinkCount == 1;

    internal static IntPtr PackWalkContextMenu(int x, int y) =>
        PackPoint(new Point { X = x, Y = y });

    internal static IntPtr PackWalkContextMenuMessage() =>
        PackMessage(WmContextMenu, 0);

    private static bool TryShowWalkContextMenu(string executablePath, Point anchor)
    {
        var expectedPath = TrayAppProvider.NormalizeExecutablePath(executablePath);
        if (!IsKnownWalkTrayClient(expectedPath)) return false;

        var matches = new List<IntPtr>();
        var after = IntPtr.Zero;
        while (true)
        {
            var window = FindWindowEx(IntPtr.Zero, after, "WalkNotifyIconSink", null);
            if (window == IntPtr.Zero) break;
            after = window;

            GetWindowThreadProcessId(window, out var processId);
            if (processId == 0) continue;
            try
            {
                using var process = Process.GetProcessById((int)processId);
                var livePath = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(livePath) ||
                    !string.Equals(
                        TrayAppProvider.NormalizeExecutablePath(livePath),
                        expectedPath,
                        StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                matches.Add(window);
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception or UnauthorizedAccessException)
            {
                // The owner can exit between enumeration and dispatch.
            }
        }

        // A GUID-to-window mapping is not exposed by Explorer. Tailscale's
        // current client creates one Walk sink per GUID icon, so only dispatch
        // when the process has exactly one candidate; never pick an arbitrary
        // sink if that contract becomes ambiguous.
        if (!ShouldDispatchWalkContextMenu(expectedPath, matches.Count)) return false;
        return PostMessage(
            matches[0],
            WalkNotifyIconMessage,
            PackPoint(anchor),
            PackWalkContextMenuMessage());
    }

    private static IntPtr PackPoint(Point point) =>
        new(unchecked((int)((uint)(ushort)point.X | ((uint)(ushort)point.Y << 16))));

    private static IntPtr PackMessage(int low, int high) =>
        new(unchecked((int)((uint)(ushort)low | ((uint)(ushort)high << 16))));

}
