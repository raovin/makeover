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
- Center: CPU, RAM, best-route network throughput, and combined battery state.
- Right: actual connection type, Bluetooth, volume, Control Center, date, and bell.
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

Windows' native taskbar remains the owner of its 48 px bottom work area and is
visually hidden while the dock runs. A transparent `WorkAreaGapForm` AppBar reserves
only the additional optical-scale height and breathing room required by the custom
dock. It reacts to AppBar position changes, re-registers after Explorer starts, and
uses bounded startup settling plus the existing taskbar guard to repair a dropped
reservation. The reservation window is pinned to the bottom of z-order: on a 96-DPI
display its 36 px reservation overlaps the enlarged dock by 24 px geometrically and
must never paint above the dock surface. Graceful shutdown removes the gap and
restores every native taskbar.
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

`Promote-NativeShell.ps1` orchestrates those phases. The optional archived rollback
uses the same split through `archive/seelen-ui/scripts/Restore-SeelenSystemProfile.ps1`
and `archive/seelen-ui/scripts/Restore-SeelenProfile.ps1`.

## Release Gates

1. Build, PowerShell parsing, dock invariants, and real Core Audio test pass.
2. Exactly one MenuBar, MenuHost, and Dock run; Seelen and YASB do not.
3. Every monitor reserves both top and bottom work areas.
4. Desktop, maximized, restored, and snapped visual checks pass at real DPI.
5. Repeated Alt+Tab works with every custom panel open and closed.
6. Apple, Network, Bluetooth, Control Center, bell, date, volume, and corners are
   behaviorally independent.
7. Explorer navigation, restart, and sign-in preserve one coherent shell.
8. MenuBar and MenuHost stay below 100 MB; Dock stays below 120 MB without growth.
9. Rollback never leaves Seelen and the native profile running together.
10. Mixed-DPI signoff is repeated whenever the external display is connected.
