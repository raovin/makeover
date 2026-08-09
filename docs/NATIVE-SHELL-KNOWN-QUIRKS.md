# Vesper Shell Known Quirks and Runbook

This document records platform behaviors that have caused misleading symptoms or
regressions in the native shell. Treat these as implementation contracts, not as
optional cleanup ideas.

## File Explorer Dock Item

The Windows `explorer.exe` process owns both the desktop shell and ordinary File
Explorer folder windows. Its `MainWindowHandle` can point at the desktop shell
(`Progman` or `WorkerW`) and can have no title. Treating that handle as a folder
window makes the Dock click appear to do nothing: `SetForegroundWindow` can report
success without opening a visible folder.

The built-in `File Explorer` pin must therefore:

- activate only current-session, visible `CabinetWClass` or `ExploreWClass`
  windows;
- ignore `Progman`, `WorkerW`, and every other shell window; and
- fall back to `%WINDIR%\explorer.exe` when no real folder window can be raised.

Do not restore the old `shell:AppsFolder\Microsoft.Windows.Explorer` fallback or
trust the pinned `File Explorer.lnk` target. On this machine that shortcut can have
an empty `TargetPath`; its icon remains useful, but it is not a reliable launch
source.

The headless contract is covered by
`MacMakeover.Dock.exe --regression-test` through
`TestFileExplorerActivationPolicy`. It must not launch Explorer or modify the
production pin state.

## AppBar Registration

`MacMakeover.MenuBar` and `MacMakeover.Dock` are Windows AppBars. `ABM_NEW` must be
treated as a success only when `SHAppBarMessage` returns a non-zero value.

For the Menu Bar:

- `TaskbarCreated` removes the previous registration before re-registering;
- startup reassertion retries only at the existing 1-second and 4-second points;
- a newly registered bar is positioned once, not twice; and
- a failed registration may position its own visible HWND for DPI correctness, but
  must never call `ABM_SETPOS` while unregistered or claim work-area space.

Do not add a permanent Menu Bar recovery timer or copy the Dock's recovery loop
into it. The Dock has a separate bounded recovery policy because its full-height
reservation must repair dropped Explorer work-area state.

## Deployment and Testing

Run promotion from a normal interactive PowerShell window in the repository:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Promote-NativeShell.ps1
```

Do not run promotion from a background agent terminal. The scheduled UI processes
can inherit that session lifetime and terminate when the background command exits.
Always promote with a full build after source changes; `-SkipBuild` can leave the
previous binaries active.

The default regression suite is nondisruptive. The explicit suite below performs
one real Alt+Tab and force-stops/recoveries for MenuHost, MenuBar, Dock, and
Supervisor, so run it only when a brief shell interruption is acceptable:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-NativeShellRegression.ps1 `
  -IncludeInteractiveAltTab -IncludeLiveRecovery
```

The live-recovery suite must finish with exactly one instance of each component
and a passing `Test-NativeShellProfile.ps1` work-area gate. It reports duplicates
instead of silently killing them.

## Visual QA Capture Path

On this machine, GDI-based `CopyFromScreen` captures can omit topmost or
non-activating overlay windows even when the window is visible, receives pointer
hit-tests, and renders correctly through `PrintWindow`. That can produce a false
missing Dock diagnosis.

Use a physical screenshot or a compositor-aware capture such as Windows Desktop
Duplication for acceptance screenshots. Do not mark the Dock or Menu Bar missing
from a GDI capture alone.

## Evidence Boundary

The latest promoted-build acceptance established:

- 13/13 regression checks passed, including real Alt+Tab and live recovery;
- top reservations of 20 px on the 1280x800 laptop and 30 px on the 1920x1080
  external display;
- bottom reservations of 56 px and 84 px respectively;
- no new shell crash, hang, .NET, or WER events after promotion; and
- zero handle growth during the idle performance sample.

Still-manual checks are physical display hotplugging and pointer-level stress of
Dock context menus. Screenshots and headless tests cannot honestly prove those
transitions.
