# Native Shell Architecture

## Objective

Keep the useful macOS-inspired layout without replacing the Windows components
that provide reliable task switching, window management, and application lifecycle.

## Ownership Boundary

| Surface | Owner |
| --- | --- |
| Top menu bar rendering and hit testing | `MacMakeover.MenuBar` |
| Apple, Control Center, Network, and Bluetooth panels | `MacMakeover.MenuHost` |
| Bottom dock rendering, pins, previews, and work area | Windows Explorer |
| Dock appearance only | Windhawk Windows 11 Taskbar Styler |
| Alt+Tab, Win+Tab, snap, maximize, Start, and Search | Windows Explorer |
| Notifications and calendar | Windows Notification Center |
| Spotlight-style launcher | PowerToys Run / Command Palette |

Seelen, YASB, custom task switchers, window movers, and polling hot-corner helpers
are not part of the production profile.

## Menu Bar

`tools/MacMakeover.MenuBar` is an owner-drawn, per-monitor-aware WinForms app.
It registers as a top AppBar, so Windows reserves its work area.

- Left: Apple mark and focused application.
- Center: CPU, RAM, best-route network throughput, and combined battery state.
- Right: actual connection type, Bluetooth, volume, Control Center, date, and bell.
- Exact top-left and top-right corners toggle Show Desktop.
- The bar remains visible for ordinary and fullscreen windows; hiding it proved too
  easy to misclassify and was removed as a reliability risk.
- Display changes rebuild one bar per active monitor.

There are no child controls, web views, plugin hosts, global mouse hooks, or
synthetic window movers. Telemetry rejects overlapping samples.

## Menus

The bar sends commands over the resident MenuHost named pipe. If the host is
missing, it starts the deployed executable without a console window.

- Apple opens only the Apple menu.
- Network opens only the live nearby-network panel.
- Bluetooth opens only the Bluetooth panel.
- Volume and sliders open Control Center.
- Date and bell open native Notification Center.

Panels paint immediately. Wi-Fi and Bluetooth settle independently in under one
second on the laptop; the slower brightness WMI probe cannot hold them up. The
Core Audio self-test changes the master volume by four percentage points, reads it
back, restores the original level, and verifies restoration.

Show Desktop enumerates real visible application windows on every invocation.
It therefore stays reversible when the user mixes the corners, Control Center,
the taskbar, and `Win+D`.

## Dock

The dock is the native Windows 11 taskbar with the official Windhawk
`windows-11-taskbar-styler` 1.7 module. The binary URL and SHA-256 are pinned in
`config/windhawk/native-dock.json`.

The profile keeps native pins, jump lists, hover previews, badges, and task
lifecycle; uses a centered fully opaque surface; hides the duplicate Start button
and tray; and disables taskbar auto-hide. No pin database is rewritten.

## Privilege Boundary

This Azure AD profile rejects Explorer HKCU changes from an elevated process.
Promotion is intentionally split:

1. `Prepare-NativeShellUserProfile.ps1` builds, deploys, registers user protocols,
   applies wallpaper/startup entries, and prepares Explorer from the normal token.
2. `Request-NativeShellPromotion.ps1` requests UAC for the narrow privileged phase.
3. `Switch-To-NativeShell.ps1` installs Windhawk and disables Seelen/hot-corner tasks.
4. `Complete-NativeShellPromotion.ps1` returns to the normal token, restarts Explorer,
   starts the owned processes, and runs live acceptance.

`Promote-NativeShell.ps1` orchestrates those phases. Rollback uses the same split
through `Restore-SeelenSystemProfile.ps1` and `Restore-SeelenProfile.ps1`.

## Release Gates

1. Build, PowerShell parsing, pinned hash, and real Core Audio test pass.
2. Exactly one MenuBar and MenuHost run; Seelen and YASB do not.
3. Every monitor reserves both top and bottom work areas.
4. Desktop, maximized, restored, and snapped visual checks pass at real DPI.
5. Repeated Alt+Tab works with every custom panel open and closed.
6. Apple, Network, Bluetooth, Control Center, bell, date, volume, and corners are
   behaviorally independent.
7. Explorer navigation, restart, and sign-in preserve one coherent shell.
8. MenuBar and MenuHost each stay below 100 MB without growth in the soak sample.
9. Rollback never leaves Seelen and the native profile running together.
10. Mixed-DPI signoff is repeated whenever the external display is connected.
