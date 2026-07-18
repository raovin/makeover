# Native Dock Replacement QA - 2026-07-18

## Decision

The Windhawk taskbar-styler dock was replaced by `MacMakeover.Dock`. On Windows
11 build 26100.8875, attempts to expand native task-button slots through either
fixed width or running-panel margins crashed `Explorer.EXE` in
`Windows.UI.Xaml.dll`. The Windhawk mod and service are now disabled in production.

## Accepted Visual Geometry

- 21 icons in manifest order.
- 28 px logical icons in 44 px logical slots.
- 42 px logical graphite frame with 22 px logical end padding and a 3 px
  top/bottom inset inside the reserved taskbar strip.
- An additional 8 px transparent appbar reservation above the hidden native
  taskbar strip keeps maximized DWM borders visibly clear of the dock frame.
- The reserved gap and outer dock strip repaint the matching wallpaper slice.
  This prevents a background fullscreen window from leaking text or scrollbars
  around the floating dock.
- The wallpaper backplate is a layered, click-through tool window. The interactive
  dock window is physically clipped to the rounded frame, so the outer strip is
  not a dead input zone.
- Laptop at 150%: 1,452 px frame and 66 px physical icon centers.
- External display at 100%: 968 px frame and 44 px physical icon centers.
- Frame stays entirely below the maximized work area on both displays.
- Packaged-app artwork resolves through `IShellItemImageFactory`; classic shortcuts
  resolve to their executable target, so no shortcut arrows remain.

## Behavioral QA

- `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` keeps the dock out of Alt+Tab.
- A real Alt+Tab switched Azure Storage Explorer to File Explorer successfully.
- Maximized and restored windows preserve the dock and do not render behind it.
- Graceful `--shutdown` restores primary and secondary Windows taskbars.
- Restart hides both native taskbars again without changing their work-area reserve.
- A 1.5-second visibility guard re-hides any primary or secondary native taskbar
  that Explorer resurfaces after an appbar topology change.
- Shutdown is guarded against recursive `ExitThread()` calls and was verified to
  release the deployed binary within the 10-second lifecycle gate.
- Dock self-test resolves all 21 manifest entries and all 21 icons.
- No global keyboard or mouse hooks are present.

## Performance And Stability

- 30-second idle sample: 0.25 CPU-seconds, approximately 0.83% of one core.
- Post-gap 15-second idle sample: 0.047 CPU-seconds, approximately 0.31% of
  one core, including the native-taskbar visibility guard.
- Working set: 96.8 MB; private memory: 34 MB.
- Running-state polling uses one process snapshot per monitor every three seconds.
- Explorer/XAML faults were recorded between 22:23 and 23:01 during the rejected
  Windhawk selector experiments and repeated Explorer restarts. No relevant
  Explorer, XAML, .NET, or MacMakeover application fault was recorded after
  midnight during the final native-shell audit.

## Automated Gates

- `Test-NativeShellPreflight.ps1`: pass with the final guard build on the active
  laptop display; the 8 px gap geometry passed earlier with both displays active.
- `Test-NativeTaskbarPins.ps1`: pass, 21/21 pins.
- `Test-NativeShellProfile.ps1`: pass.
- `dotnet build`: zero warnings and zero errors.
- PowerShell parser sweep: pass.
- `git diff --check`: pass.

Local screenshot evidence is under `qa/native-dock-*` and is intentionally ignored
by Git.

Windows exposed only the laptop display during the final post-guard screenshot.
The profile gate now enumerates both `Shell_TrayWnd` and
`Shell_SecondaryTrayWnd`; repeat the final external-display screenshot when that
display is active again.

## Final Release Audit - 2026-07-19

- Rebuilt and deployed the exact checked-out source after every accepted fix.
- Ran five complete Dock shutdown/relaunch cycles, then three more after the final
  wallpaper-backplate change. Every stopped state restored one native taskbar and
  a 48 px bottom reserve; every running state restored the 56 px reserve, hid the
  native taskbar, and left exactly one Dock process.
- Broadcast three consecutive `WM_DISPLAYCHANGE` events. The same Dock process
  remained responsive, with stable window ownership and work-area geometry.
- Marshalled display rebuilds to the WinForms UI thread and deduplicated concurrent
  monitor events with an interlocked guard.
- Exercised Apple, Control Center, Wi-Fi, Bluetooth, and Notification Center panels;
  verified menu dismissal and application switching through Alt+Tab.
- Verified `Win+D` show-desktop and restore as a round trip.
- Activated Chrome and ChatGPT with real dock clicks using DPI-aware coordinates.
- Changed brightness from 99% to 41% and restored 99% through the visible slider.
- Ran the MenuHost Core Audio self-test, including volume change, verification, and
  restoration. The test exited successfully.
- Corrected Control Center's full-battery label so 100% no longer claims to be
  charging when the menu bar correctly shows a full battery.
- The final 30-second sample measured 0.477% median custom-shell CPU, 0.769% p95 CPU,
  186.8 MB median working set, and 61.5 MB median private memory across MenuBar,
  MenuHost, and Dock.
- Rejected an intermediate wallpaper-backdrop build after visual QA exposed a
  zero-size first-paint exception. The final build guards that path and passed a
  fresh restart, screenshot, and profile check.
- Hit-test probes on the final build resolved the left and right outer strip to
  the underlying desktop, while the dock center alone resolved to the Dock process.
- Final laptop screenshot: `qa/release-audit-final-signoff.png`.

Final gates: clean publish, zero compiler warnings/errors, preflight pass, 21/21
inherited pins present, live profile pass, aggregate verifier pass, and
`git diff --check` pass. The physically disconnected external display remains the
only visual signoff that could not be repeated on the final guard build.
