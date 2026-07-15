# mac-makeover

A macOS-inspired Windows 11 desktop that keeps Windows responsible for the
things Windows must do reliably.

The current production profile uses Seelen UI for the full-width menu bar and
WEG dock, with the repository's macOS glass theme and MenuHost panels. A YASB
and native-taskbar migration was evaluated on July 14-15, 2026 and rolled back
after failing laptop mixed-DPI, wallpaper, dock, and responsiveness acceptance.

## Design Contract

- Native Windows Alt+Tab, maximize, snap, Start, Search, notifications, audio,
  networking, taskbar previews, and Show Desktop must keep working.
- A maximized app must fit between the top bar and taskbar. No window mover or
  polling helper is allowed to correct geometry after the fact.
- The top bar keeps focused app information on the left, CPU/RAM/network in the
  center, and distinct system controls on the right.
- One control opens one surface. The Apple mark, network, Bluetooth, volume,
  Control Center, notifications, and calendar must not all open the same panel.
- Visual polish is optional; shell reliability is a release gate.

## Production Architecture

### Top menu bar

Seelen Fancy Toolbar owns the menu bar on each display.

- **Left:** Apple mark and active app
- **Center:** CPU, RAM, and live network throughput
- **Right:** network, Bluetooth, combined battery/charging state, real volume
  menu, Control Center, notifications, and `Tue 14 Jul 23:04` style date/time

The accepted state is stored under `config/seelen/`; Seelen shortcuts and its
task switcher/window manager stay disabled so Windows retains Alt+Tab, snapping,
and ordinary window management.

### Bottom dock

Seelen WEG owns the opaque bottom dock and reserves the bottom work area. The
native taskbar remains auto-hidden. Maximized applications must stop above WEG;
`scripts/verify.ps1` and visual QA both gate that behavior.

### Menus

`tools/MacMakeover.MenuHost` is a small resident WinForms process for the custom
Apple, Control Center, Network, and Bluetooth panels. Toolbar callbacks use
registered `macmakeover-*:` protocols and a named pipe, so no visible terminal
is launched and panels appear without stealing Alt+Tab focus.

The Control Center has working display and Core Audio sliders. Show Desktop uses
the verified reversible `MinimizeAll` / `UndoMinimizeAll` path.

### Search

`Alt+Space` remains the Spotlight-style launcher through Microsoft Command
Palette / PowerToys Run. The stored launcher settings prioritize local apps,
files, calculator, windows, settings, and custom commands. Bing/web results are
suppressed by the packaged user-level search settings.

## Install Or Restore

Open PowerShell in this repository:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\restore.ps1 -ApplyWallpaper
```

For recovery after the abandoned native-shell experiment, run
`scripts\Restore-SeelenProfile.ps1`; it reinstalls Seelen when necessary, stops
YASB, restores the accepted profile and wallpaper, starts the helper services,
and restores taskbar auto-hide.

## Verify

Run the production smoke test:

```powershell
.\scripts\verify.ps1
```

Release signoff must also cover these manual interactions on both displays:

1. Alt+Tab repeatedly with every custom panel open and closed.
2. Maximize, restore, minimize, snap, and fullscreen ordinary applications.
3. Open Apple, network, Bluetooth, volume, Control Center, notifications, and
   calendar independently.
4. Move the real volume slider and restore its original value.
5. Use Show Desktop twice and verify windows restore.
6. Open Start, Search, taskbar previews, tray overflow, and native quick settings.
7. Disconnect/reconnect Wi-Fi and power, then verify status icons update.
8. Reboot and repeat the visual check before calling the profile complete.

Generated QA screenshots belong under `qa/` and should not be committed unless
they are a deliberately selected acceptance artifact.

## Rollback

The retired native-shell experiment remains reversible for investigation, but
is not the accepted profile. To return to production:

```powershell
.\scripts\Restore-SeelenProfile.ps1
```

Rollback stops YASB, disables its autostart, reinstalls Seelen if necessary,
restores the portable toolbar/dock/theme snapshot and wallpaper, restores the
previous taskbar auto-hide preference, and starts the helper profile.

## Repository Layout

```text
config/
  seelen/               Production toolbar, dock, theme, and plugin snapshot
  yasb/                 Retired native-shell experiment
  windhawk/             Retired native-taskbar experiment notes
  powertoys/             Spotlight-style launcher settings
scripts/
  restore.ps1           Restore the production profile
  Restore-SeelenProfile.ps1
  Install-NativeShell.ps1       Retired experiment
  Switch-To-NativeShell.ps1     Retired experiment
  Test-NativeShellProfile.ps1   Experiment-only verifier
  Install-*Handler.ps1  Custom protocol registration
tools/
  MacMakeover.MenuHost/ Resident Apple/Control Center panel host
docs/                   Historical handovers, reviews, and migration notes
assets/                 Wallpapers, cursors, and source assets
```

## Safety And Portability

- No credentials, RustDesk passwords, Tailscale keys, browser sessions, or work
  tokens are intentionally stored.
- Restart, shutdown, sleep, and log out require confirmation in MenuHost.
- Seelen and MenuHost are user-facing shell enhancements; Seelen's task switcher
  and window manager are deliberately disabled.
- The hot-corner helper is limited to guarded exact-corner and mixed-DPI fallback
  behavior, with its click zones checked by `scripts\verify.ps1`.
- Review paths and registry exports before making the repository public.

The repository remote is `git@github.com:raovin/makeover.git`.
