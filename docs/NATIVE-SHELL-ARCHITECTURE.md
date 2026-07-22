# Native Shell Architecture

## Objective

Keep the useful macOS-inspired layout without replacing the Windows components
that provide reliable task switching, window management, and application lifecycle.

## Ownership Boundary

| Surface | Owner |
| --- | --- |
| Top menu bar rendering and hit testing | `MacMakeover.MenuBar` |
| Apple, Control Center, Network, and Bluetooth panels | `MacMakeover.MenuHost` |
| Bottom dock rendering and pin actions | `MacMakeover.Dock` |
| Sleep prevention and optional Teams activity tray control | `AwakeAndAvailable` |
| App switching, snap, maximize, and lifecycle | Windows Explorer |
| Alt+Tab, Win+Tab, snap, maximize, Start, and Search | Windows Explorer |
| Notifications and calendar | Windows Notification Center |
| Spotlight-style launcher | PowerToys Run / Command Palette |

Seelen, YASB, custom task switchers, window movers, and polling hot-corner helpers
are not part of the production profile.

## Menu Bar

`tools/MacMakeover.MenuBar` is an owner-drawn, per-monitor-aware WinForms app.
It registers as a top AppBar, so Windows reserves its work area.

The current visual target is captured in
[`concepts/native-shell-graphite.png`](concepts/native-shell-graphite.png).

- Left: Apple mark and focused application.
- Center: CPU, RAM, best-route network throughput, explicit battery/charging
  source, and the active Windows AC/DC power mode.
- Right: every live notification-area app extra, actual connection type, Bluetooth,
  volume, Control Center, date, and bell. Tray-first apps stay out of the dock, use
  their real registered icon, and activate directly from the menu bar.
- Segoe UI Variable Text and its native semibold face render every text cluster on
  one baseline. Native hinting keeps the 100% external display as crisp as the
  150% laptop panel; geometry and type receive separate optical scaling.
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

`tools/MacMakeover.Dock` is an owner-drawn, per-monitor WinForms surface. It uses
`WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`, so it cannot take focus and never appears in
Alt+Tab. It does not install keyboard or mouse hooks.

The dock loads all 21 inherited pins from `config/native-taskbar-pins.json`, resolves
classic shortcut and packaged-app artwork through the Windows shell, spaces 28 px
logical icons in deterministic 44 px slots, and paints icons, hover lift, and live
running dots directly onto the same buffered surface as the frame. It deliberately
has no transparent child controls: WinForms child transparency composites against a
fallback color and creates black icon tiles. Clicking an item focuses a matching
window or asks the shell to launch the pinned app.

Taskbar-eligible windows from unpinned applications are enumerated once per second,
grouped by executable, and appended as transient dock items. Multiple windows from
one app share one icon; the item disappears after the last real window closes.
Owned dialogs, cloaked windows, tool windows, lock/sign-in surfaces, and the shell's
own processes are excluded. Packaged apps hosted by `ApplicationFrameHost` are
separated by window title and deduplicated against their concrete process so Settings
and simultaneous hosted apps each receive one item. Slot spacing contracts only when
needed to keep a busy dock inside the current display.
`--snapshot-running <path>` exposes the live classification as JSON for regression QA.

Windows' native taskbar windows remain alive for Explorer ownership but are visually
hidden while the dock runs. Hidden taskbars no longer retain work-area reservations
on current Windows builds, so a transparent `WorkAreaGapForm` AppBar owns the full
visual dock height plus its 8 px breathing room. Explorer records that full reserved
rectangle, while the AppBar's actual HWND is a nonpainting 1 px anchor at the bottom
edge. This leaves Windows' real wallpaper visible around the dock and prevents a
separate wallpaper approximation from creating a horizontal seam. The AppBar reacts
to position changes, re-registers after Explorer starts, and uses bounded startup
settling plus the taskbar guard to repair a dropped reservation. The same guard repairs
a hidden, de-topmost, or fullscreen-occluded dock surface without activating it.
Graceful shutdown removes the gap and restores every native taskbar.
The dock has no custom task switcher, window mover, or Explorer injection. Windhawk's
taskbar styler remains installed as rollback material, disabled with its service manual.

## Privilege Boundary

This Azure AD profile rejects Explorer HKCU changes from an elevated process.
Promotion is intentionally split:

1. `Prepare-NativeShellUserProfile.ps1` builds, deploys, registers user protocols,
   applies wallpaper/startup entries, and prepares Explorer from the normal token.
2. `Request-NativeShellPromotion.ps1` requests UAC for the narrow privileged phase.
3. `Switch-To-NativeShell.ps1` disables the legacy Windhawk profile and Seelen tasks.
4. `Complete-NativeShellPromotion.ps1` returns to the normal token, restarts Explorer,
   starts the owned processes, and runs live acceptance.

The privileged phase also sets the ADMX Desktop Wallpaper policy to `CropToFit`
(`4`; Windows' ordinary desktop key uses `10` for the same Fill result) and registers
`MacMakeover Wallpaper Guard`. The hidden task runs at logon and every 15 minutes to
repair device-management reapplication without adding a resident polling process.
Promotion removes the retired hot-corner Startup shortcut; the owned AppBar handles
both corners directly.

`Promote-NativeShell.ps1` orchestrates those phases. The optional archived rollback
uses the same split through `archive/seelen-ui/scripts/Restore-SeelenSystemProfile.ps1`
and `archive/seelen-ui/scripts/Restore-SeelenProfile.ps1`.

## Release Gates

1. Build, PowerShell parsing, dock invariants, and real Core Audio test pass.
2. Exactly one MenuBar, MenuHost, Dock, and managed Awake & Available process run;
   Seelen and YASB do not.
3. Every monitor reserves both top and bottom work areas.
4. Desktop, maximized, restored, and snapped visual checks pass at real DPI.
5. Repeated Alt+Tab works with every custom panel open and closed.
6. Apple, Network, Bluetooth, Control Center, bell, date, volume, and corners are
   behaviorally independent.
7. Explorer navigation, restart, and sign-in preserve one coherent shell.
8. Unpinned Edge, Notepad, and packaged Windows apps appear while open and disappear
   after their last taskbar window closes; pinned items remain stable.
9. MenuBar and MenuHost stay below 100 MB; Dock stays below 120 MB without growth.
10. Rollback never leaves Seelen and the native profile running together.
11. Mixed-DPI signoff is repeated whenever the external display is connected.
