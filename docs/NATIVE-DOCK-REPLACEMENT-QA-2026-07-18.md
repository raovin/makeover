# Native Dock Replacement QA - 2026-07-18

## Decision

The Windhawk taskbar-styler dock was replaced by `MacMakeover.Dock`. On Windows
11 build 26100.8875, attempts to expand native task-button slots through either
fixed width or running-panel margins crashed `Explorer.EXE` in
`Windows.UI.Xaml.dll`. The Windhawk mod and service are now disabled in production.

## Accepted Visual Geometry

- 21 icons in manifest order.
- 28 px logical icons in 44 px logical slots.
- 46 px logical graphite frame with 22 px logical end padding.
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
- Dock self-test resolves all 21 manifest entries and all 21 icons.
- No global keyboard or mouse hooks are present.

## Performance And Stability

- 30-second idle sample: 0.25 CPU-seconds, approximately 0.83% of one core.
- Working set: 96.8 MB; private memory: 34 MB.
- Running-state polling uses one process snapshot per monitor every three seconds.
- Zero Explorer application faults were recorded after Windhawk was removed from
  Explorer and its service was stopped.

## Automated Gates

- `Test-NativeShellPreflight.ps1`: pass on both displays.
- `Test-NativeTaskbarPins.ps1`: pass, 21/21 pins.
- `Test-NativeShellProfile.ps1`: pass.
- `dotnet build`: zero warnings and zero errors.
- PowerShell parser sweep: pass.
- `git diff --check`: pass.

Local screenshot evidence is under `qa/native-dock-*` and is intentionally ignored
by Git.
