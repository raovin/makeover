# mac-makeover

A macOS-inspired Windows 11 desktop that keeps Windows responsible for the
things Windows must do reliably.

The current production profile uses a lightweight YASB menu bar, the native
Windows taskbar, and an optional one-mod Windhawk skin. Seelen UI is retained in
Git history and portable config snapshots, but is no longer installed or used.

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

[YASB](https://github.com/amnweb/yasb) owns a 26 logical-pixel Windows appbar on
each display. It reserves real work area and uses no keyboard hooks.

- **Left:** Apple mark and active app
- **Center:** CPU, RAM, and live network throughput
- **Right:** network, Bluetooth, combined battery/charging state, real volume
  menu, Control Center, notifications, and `Tue 14 Jul 23:04` style date/time

Mixed-DPI dimensions are explicit in `config/yasb/config.yaml`. Live config and
stylesheet reload are disabled because appbar re-registration during reload can
destabilize the Windows work area. Updates use a clean `yasbc stop/start`.

### Bottom dock

The bottom surface is the native Windows taskbar with auto-hide disabled. This
is deliberate: it reserves work area, owns real app buttons and previews, and
cannot break Alt+Tab by replacing the shell.

For a dock-like appearance, install only Windhawk's official **Windows 11
Taskbar Styler** mod and choose its integrated **DockLike** theme. See
`config/windhawk/README.md`.

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
.\scripts\Install-NativeShell.ps1
```

That installs YASB and Windhawk if needed, deploys the YASB profile, disables
taskbar auto-hide, registers MenuHost protocols, enables YASB autostart, stops
Seelen/hot-corner helpers, and starts the production profile.

Windhawk's taskbar skin is intentionally a separate manual step:

1. Open Windhawk.
2. Install **Windows 11 Taskbar Styler** by m417z.
3. In its Settings tab, select **DockLike** and save.

The system remains fully usable if Windhawk or the mod is disabled.

## Verify

Run the production smoke test:

```powershell
.\scripts\Test-NativeShellProfile.ps1
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

The native-shell migration is reversible:

```powershell
.\scripts\Restore-SeelenProfile.ps1
```

Rollback stops YASB, disables its autostart, reinstalls Seelen if necessary,
restores its startup task when permissions allow, restores the previous taskbar
auto-hide preference, and re-enables the old helper profile.

## Repository Layout

```text
config/
  yasb/                 Production top-bar config, stylesheet, and Apple asset
  windhawk/             Optional native-taskbar skin instructions
  seelen/               Historical portable Seelen snapshot for rollback
  powertoys/             Spotlight-style launcher settings
scripts/
  Install-NativeShell.ps1
  Switch-To-NativeShell.ps1
  Test-NativeShellProfile.ps1
  Restore-SeelenProfile.ps1
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
- YASB and MenuHost are user processes. Windhawk is optional and limited to one
  official taskbar styling mod in the baseline.
- The old Seelen hot-corner helper is disabled because global polling and click
  routing previously interfered with navigation and system switching.
- Review paths and registry exports before making the repository public.

The repository remote is `git@github.com:raovin/makeover.git`.
