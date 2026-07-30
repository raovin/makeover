# Vesper Shell (mac-makeover)

Vesper Shell is a macOS-inspired Windows 11 desktop shell that keeps Windows in charge of productivity.

The production profile uses an owned native menu bar, small native menu panels,
and a no-activation native dock. The retired Seelen UI
generation is preserved under `archive/seelen-ui/` only for reference or rollback.

## What You Get

- Apple mark and focused app at the left of a 20 px logical menu bar.
- The original Seelen `Big Sur (Day)` 6K wallpaper, preserved and managed locally.
- Crisp Segoe UI Variable Text typography, optically scaled for mixed-DPI displays.
- Symbolic CPU, RAM, and network-throughput readouts, gently biased left to
  preserve room for the right-side controls, followed by explicit battery,
  charging-source, and Windows power-mode state.
- Separate Wi-Fi, Bluetooth, volume, Control Center, date, and notification controls.
- Apple-style power and session commands without the old full-screen launcher.
- A centered opaque dock with the inherited pin set, live running apps and
  persistent `Pin to Dock` / `Remove from Dock` actions.
- Spotlight-style local search through `Alt+Space`, with Bing results suppressed.
- Native Explorer ownership of Alt+Tab, Win+Tab, snap, maximize, Start, and Search.

## Reliability Contract

- Maximized apps must fit between the menu bar and dock.
- The bar and dock must remain present for maximized, restored, and desktop states.
- One control opens one surface; Wi-Fi and Bluetooth never open the generic panel.
- Menus must dismiss immediately when Alt+Tab starts.
- Show Desktop must remain reversible even when mixed with `Win+D`.
- No polling window mover, replacement task switcher, DOM toolbar, or Seelen service
  is allowed in the production profile.
- The retired hot-corner Startup shortcut must remain absent; the native AppBar owns
  both Show Desktop corners without a global mouse hook.
- Managed wallpaper policy must use the ADMX `CropToFit` value (`4`) and the hidden
  repair task must preserve it across device-management refreshes.
- Visual polish is not accepted until screenshot QA passes on the actual desktop.

## Architecture

| Surface | Owner |
| --- | --- |
| Top bar | `MacMakeover.MenuBar` (.NET WinForms AppBar) |
| Apple and system panels | `MacMakeover.MenuHost` (.NET WinForms) |
| Dock rendering and pin actions | `MacMakeover.Dock` (.NET WinForms tool window) |
| App switching and window lifecycle | Windows Explorer |
| Notifications and calendar | Windows Notification Center |
| Spotlight-style launcher | Microsoft Command Palette / PowerToys Run |

See [Native Shell Architecture](docs/NATIVE-SHELL-ARCHITECTURE.md) for ownership,
security boundaries, and release gates. The measured native-versus-Seelen resource
comparison is in [Performance Comparison](docs/PERFORMANCE-COMPARISON-2026-07-17.md).
The latest two-display signoff is in
[Mixed-DPI QA](docs/NATIVE-SHELL-QA-2026-07-20.md).
The post-restart regression analysis and current acceptance boundary are in
[Restart Regression QA](docs/NATIVE-SHELL-REGRESSION-QA-2026-07-21.md).
The Wi-Fi outage, memory analysis, Windows repair, rollback material, and firmware
follow-up are recorded in
[System Reliability Audit](docs/SYSTEM-RELIABILITY-AUDIT-2026-07-22.md).

## Install Or Upgrade

Open a normal interactive PowerShell session in this repository. Do not start it as
administrator; the script requests elevation only for the legacy-mod and scheduled
task phase. Do not launch the promoter from a background agent terminal: the person
at the desktop must run it in their own interactive session.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\Promote-NativeShell.ps1
```

Approve the one Windows UAC prompt. The promoter builds and stages the binaries,
checks Core Audio and dock invariants, applies the privileged phase,
restarts Explorer once, starts each shell component through its own interactive
scheduled task, and runs acceptance checks. A lightweight native watchdog re-runs
any component task that exits unexpectedly. The task boundary keeps the shell alive
after a successful interactive installation.

To verify an existing installation without changing it:

```powershell
.\scripts\Test-NativeShellPreflight.ps1 -SkipDownloadCheck
.\scripts\Test-NativeShellProfile.ps1
.\scripts\Test-NativeTaskbarPins.ps1
```

To run the repeatable native-shell regression suite, including a safe missing-process
performance smoke test:

```powershell
.\scripts\Test-NativeShellRegression.ps1
```

The explicit interaction and recovery gates are opt-in because they perform one real
Alt+Tab and intentionally terminate/recover MenuHost and the Supervisor:

```powershell
.\scripts\Test-NativeShellRegression.ps1 -IncludeInteractiveAltTab -IncludeLiveRecovery
```

Timestamped JSON evidence and performance samples are written under `qa/regression/`
and remain local.

## Rollback

Run rollback from a normal PowerShell session. It requests elevation only to
disable the native profile and re-enable the Seelen scheduled task; user-profile state
is restored after returning to the normal token. Rollback also removes all four
native-shell startup tasks so the two shells cannot race at the next sign-in.

```powershell
.\archive\seelen-ui\scripts\Restore-SeelenProfile.ps1
```

## Repository Layout

```text
assets/                         Wallpapers and visual assets
archive/seelen-ui/              Retired Seelen profile, scripts, and history
config/windhawk/native-dock.json Archived Windhawk rollback profile
config/native-taskbar-pins.json  Required dock pins inherited from Seelen
%LOCALAPPDATA%/MacMakeover/config/dock-pins.json  Per-user Dock pin overrides
config/powertoys/               Spotlight-style launcher settings
scripts/Promote-NativeShell.ps1 Production installer/orchestrator
scripts/Test-NativeShell*.ps1   Preflight and live acceptance checks
scripts/Test-NativeShellRegression.ps1 Repeatable interaction and recovery suite
scripts/Measure-ShellPerformance.ps1 Restart-safe native process sampler
archive/seelen-ui/scripts/      Optional legacy rollback utilities
tools/MacMakeover.MenuBar/      Owned per-monitor top AppBar
tools/MacMakeover.MenuHost/     Apple and system panels
tools/MacMakeover.Dock/         No-activation mixed-DPI dock
docs/                           Architecture, QA, and historical notes
qa/                             Local visual evidence (normally uncommitted)
```

## Safety And Portability

- No credentials, remote-access passwords, browser sessions, or work tokens are
  intentionally stored.
- Restart, shutdown, sleep, and log out require confirmation.
- Windhawk remains installed for rollback, with its styler disabled and service set to manual.
- The active shell uses Windows' native variable text faces; bundled OFL fonts are
  retained as portable legacy/rollback material and need no machine-wide install.
- The external display must be physically connected before mixed-DPI signoff.
- Review registry exports and local paths before publishing a fork.

The configured remote is `git@github.com:raovin/makeover.git`.
