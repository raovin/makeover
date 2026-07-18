# mac-makeover

A macOS-inspired Windows 11 shell that keeps Windows in charge of productivity.

The production profile uses an owned native menu bar, small native menu panels,
and a no-activation native dock. The retired Seelen UI
generation is preserved under `archive/seelen-ui/` only for reference or rollback.

## What You Get

- Apple mark and focused app at the left of a 20 px logical menu bar.
- Privately loaded Manrope labels and JetBrains Mono telemetry, bundled under OFL.
- CPU, RAM, network throughput, and combined battery/charging state in the center.
- Separate Wi-Fi, Bluetooth, volume, Control Center, date, and notification controls.
- Apple-style power and session commands without the old full-screen launcher.
- A centered opaque dock with the complete inherited pin set and live running indicators.
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

## Install Or Upgrade

Open a normal PowerShell session in this repository. Do not start it as
administrator; the script requests elevation only for the legacy-mod and scheduled
task phase.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\Promote-NativeShell.ps1
```

Approve the one Windows UAC prompt. The promoter builds and stages the binaries,
checks Core Audio and dock invariants, applies the privileged phase,
restarts Explorer once, and runs acceptance checks.

To verify an existing installation without changing it:

```powershell
.\scripts\Test-NativeShellPreflight.ps1 -SkipDownloadCheck
.\scripts\Test-NativeShellProfile.ps1
.\scripts\Test-NativeTaskbarPins.ps1
```

## Rollback

Run rollback from a normal PowerShell session. It requests elevation only to
disable the native profile and re-enable the Seelen scheduled task; user-profile state
is restored after returning to the normal token.

```powershell
.\archive\seelen-ui\scripts\Restore-SeelenProfile.ps1
```

## Repository Layout

```text
assets/                         Wallpapers and visual assets
archive/seelen-ui/              Retired Seelen profile, scripts, and history
config/windhawk/native-dock.json Archived Windhawk rollback profile
config/native-taskbar-pins.json  Required dock pins inherited from Seelen
config/powertoys/               Spotlight-style launcher settings
scripts/Promote-NativeShell.ps1 Production installer/orchestrator
scripts/Test-NativeShell*.ps1   Preflight and live acceptance checks
scripts/Measure-ShellPerformance.ps1 Reproducible process sampler
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
- Bundled Manrope and JetBrains Mono files include their OFL license texts and do
  not require a machine-wide font installation.
- The external display must be physically connected before mixed-DPI signoff.
- Review registry exports and local paths before publishing a fork.

The configured remote is `git@github.com:raovin/makeover.git`.
