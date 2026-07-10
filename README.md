# mac-makeover

Portable backup and restore package for the Windows 11 macOS-style desktop setup.

This repo is the single home and source of truth for the macOS makeover, so a new Windows machine can be rebuilt from here instead of relying on the old machine as the migration source. A frozen historical copy still lives under `brunel\workspace\desktop\mac-makeover`, but that is a backup only and is no longer the working location. This repo captures the repeatable parts of the setup: Seelen UI layout/theme, dock and menu-bar configuration, wallpaper assets, cursor assets, user-level appearance exports, and restore scripts.

Keep this repo private unless you have reviewed the app paths and registry exports. No credentials are intentionally stored here, but the package does include local app names, install paths, appearance settings, and dock pins.

## What You Get

- A macOS-style top menu bar using Seelen UI.
- A bottom dock owned by Seelen WEG. The experimental native MenuHost appbar dock was removed after it interfered with maximize/work-area behavior.
- The custom `macos-glass` theme for the frosted menu bar and dock.
- The current toolbar layout: Apple-style mark, focused app, and right-side Network, Bluetooth, battery, Control Center sliders, date/time, and notification controls.
- A Mac-style Apple menu on the top-left Apple mark, opened by an item-owned `macmakeover-apple-menu:` click through the fast resident MenuHost pipe so it appears quickly and no terminal window appears.
- A custom Mac-style Control Center / power popover from the top-right sliders control, replacing Seelen's built-in quick-settings flyout and avoiding slow URI launches.
- Seelen shortcuts disabled so native Windows Alt+Tab and lock-screen input remain normal.
- Spotlight-style search through PowerToys / Command Palette on `Alt+Space`.
- Windows Search web/Bing result suppression for the current user.
- macOS-style hot corners:
  - top-left/top-right outer-corner click: show desktop
  - dwell actions disabled, including bottom corners, to avoid accidental lock/sleep/show-desktop while navigating windows
- Start-menu backed custom Spotlight commands such as `Mac Visual QA`, `Mac Backup Makeover`, and `Mac Hot Corners Stop`.
- Wallpaper and cursor assets for optional polish.
- Scripts for install, restore, verification, and refreshing this backup.

## What Is Not Stored

This package deliberately excludes machine/account state:

- RustDesk passwords, IDs, config, or unattended-access secrets.
- Tailscale auth keys, machine keys, tailnet device state, or login URLs.
- Seelen logs, cache files, generated indexes, and `.bak` files.
- Windows Security settings.
- Browser sessions, work-account tokens, app credentials, or private keys.

## Folder Layout

```text
mac-makeover/
  assets/
    cursors/              # Optional macOS-style cursor files
    source-scripts/       # Original helper scripts from the first setup
    wallpapers/           # Wallpaper source images
  config/
    command-palette/      # Microsoft Command Palette settings
    hot-corners.json      # Configurable macOS-style screen-corner actions
    powertoys/            # PowerToys launcher settings
    seelen/               # Portable Seelen UI config snapshot
  docs/
    migration-checklist.md
    CODEX-HANDOVER.md     # Historical project handover, sanitized
    CLAUDE.mac-makeover.md # Seelen/Apple-menu guardrails for Claude Code
    CLAUDE-DESIGN-PROMPT.md # Paste-ready prompt for a Claude Design visual pass
    SPEC-KIT-REVIEW-PROMPT.md # Paste-ready full audit/recovery prompt
  registry/               # User-level appearance registry exports
  scripts/
    backup-current.ps1    # Refresh this package from the current machine
    install-apps.ps1      # Install Seelen, optionally RustDesk/Tailscale
    install-hot-corners.ps1
    install-spotlight-shortcuts.ps1
    fit-windows-to-workarea.ps1 # One-shot repair for stale full-screen app bounds behind the dock
    Install-AppleMenuHandler.ps1  # Registers the Apple-menu protocol (conhost --headless)
    Show-MacAppleMenu.ps1         # Fallback Apple menu UI (WPF protocol path)
    Install-MacControlCenterHandler.ps1 # Registers the Control Center protocol
    Show-MacControlCenter.ps1     # Fallback Control Center UI (WPF protocol path)
    start-hot-corners.ps1
    stop-hot-corners.ps1
    restore.ps1           # Restore config/theme/assets to a machine
    verify.ps1            # Check files, Seelen process health, logs, screenshot
  CLAUDE.md               # Entry point for Claude Code
  tools/
    MacMakeover.MenuHost/  # Resident owner-drawn Apple/Control Center/Network/Bluetooth host
  manifest.json           # Backup metadata and exclusions
  README.md
```

## Restore On A New Windows Machine

Clone the repo, then open PowerShell in this folder:

```powershell
cd C:\path\to\mac-makeover
```

If local script execution is blocked, allow it for this PowerShell session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Install the core desktop apps:

```powershell
.\scripts\install-apps.ps1
```

Install remote-access tools too, if wanted:

```powershell
.\scripts\install-apps.ps1 -IncludeRemoteTools
```

Restore the Seelen layout/theme, Spotlight-style launcher settings, and Bing-free search preferences:

```powershell
.\scripts\restore.ps1
```

That also registers the top-left Apple menu handler, top-right Control Center handler, hot corners, and searchable Start Menu shortcuts for the launcher. To restore without those extras:

```powershell
.\scripts\restore.ps1 -SkipHotCorners -SkipSpotlightShortcuts
```

Optionally apply wallpaper, cursors, and accent registry exports:

```powershell
.\scripts\restore.ps1 -ApplyWallpaper -ApplyCursors -ApplyAccent
```

Verify the restored setup:

```powershell
.\scripts\verify.ps1 -CaptureScreenshot
```

The QA run saves a full desktop capture plus top and bottom crops under `qa/`. It prefers FFmpeg desktop capture because that sees layered Seelen UI more reliably than the basic Windows screenshot API.

## Spotlight And Hot Corners

`Alt+Space` is the primary launcher. The restore script keeps Command Palette and PowerToys Run focused on local actions: apps, files, calculator, windows, system commands, clipboard history, bookmarks, settings, and custom shortcuts. Web search, WinGet, registry, services, remote desktop, and similar noisy providers are disabled.

Custom commands are installed as normal Start Menu shortcuts under:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Mac Makeover
```

Because they are normal shortcuts, they appear naturally in Command Palette / PowerToys search.

Hot corners and menu-bar click routing are managed by a lightweight PowerShell background helper. The installer creates a current-user Startup shortcut:

```powershell
.\scripts\install-hot-corners.ps1 -StartNow
.\scripts\stop-hot-corners.ps1
```

Change the corner behavior in:

```text
config\hot-corners.json
```

Supported hover and click actions are `Spotlight`, `TaskView`, `ShowDesktop`, `Lock`, `Sleep`, `ClipboardHistory`, `NetworkFlyout`, `QuickSettings`, and `None`. The shipped config keeps dwell actions set to `None` and keeps only tiny top-left/top-right click zones for Show Desktop.

The Apple mark and normally responsive right-side controls are item-owned: Apple opens `macmakeover-apple-menu:`, Network and Bluetooth use custom MenuHost panels, Battery/sliders open `macmakeover-control-center:`, and bell/date route to native Notification Center. Seelen 2.7.4 exposes a click-through toolbar on the current mixed-DPI primary display, so the helper also carries six non-overlapping compatibility zones limited to the actual reserved toolbar height. The helper switches its polling thread to per-monitor DPI awareness so physical mouse pixels, monitor bounds, and scaled offsets share one coordinate space. Those zones run only when `WindowFromPoint` proves Seelen did not receive the click, preventing app-chrome and double-fire regressions.

## Manual Steps After Restore

Some setup must remain manual because it is account/device-specific:

- Sign into Tailscale.
- Sign into or configure RustDesk on the new device.
- Grant any remote-control permissions required by the OS.
- Approve installer or UAC prompts yourself.
- Confirm Seelen starts at login for the top menu bar and WEG dock, and the hot-corners/MenuHost helper starts for the custom menus.
- Check dock pins whose app paths differ on the new machine. The visible dock is Seelen WEG, using the saved `seelen-weg\state.yml` pin file.
- If the managed Windows Search policy key is locked by your organization, `restore.ps1` will warn and still apply the normal per-user Bing/web-search suppression values.

On managed work devices, wallpaper may be controlled by policy. The restore script attempts a user-level wallpaper change only; it does not bypass policy.

## Refresh This Backup

After making visual changes on a machine you trust, refresh the portable snapshot:

```powershell
.\scripts\backup-current.ps1
```

Review exactly what changed:

```powershell
git status --short
git diff
```

Commit the refreshed snapshot from the repo root:

```powershell
git add .
git commit -m "Update mac makeover backup"
```

The `origin` remote is `git@github.com:raovin/makeover.git`. Push reviewed commits with `git push origin main` when the local recovery stack is ready.

## Safety Notes

- `restore.ps1` backs up any existing Seelen config to `%TEMP%` before overwriting it.
- `restore.ps1` stops Seelen before copying config, then restarts it through the Seelen scheduled task when available.
- `restore.ps1` backs up existing PowerToys config before copying launcher settings when PowerToys is installed.
- `restore.ps1` installs hot-corner startup integration and Spotlight custom shortcuts unless skipped.
- `settings_shortcuts.json` is forcibly restored as disabled:

```json
{"enabled":false,"shortcuts":{}}
```

This is intentional. It keeps native Windows Alt+Tab and lock-screen PIN entry from being intercepted by Seelen shortcut/task-switcher behavior.

The launcher behavior is separate from Seelen:

- Clicking the top-left Apple mark opens the compact Apple menu for About This Mac, System Settings, App Store, Recent Items, Force Quit, Sleep, Restart, Shut Down, Lock Screen, and Log Out.
- Restart, Shut Down, and Log Out ask for confirmation.
- Normal Apple clicks are item-owned from the toolbar and open `macmakeover-apple-menu:`. The protocol writes `apple` into the resident `tools\MacMakeover.MenuHost` pipe through `conhost.exe --headless cmd`, with a `--show apple` fallback. Registering it directly to a visible PowerShell window can show a terminal. `wscript.exe`/VBS launchers are blocked by this machine's Defender/ASR policy and are intentionally not packaged.
- `scripts\install-hot-corners.ps1` starts the helper and resident MenuHost. `verify.ps1` fails if the host is missing/not running, if the helper is running under `pwsh.exe`, if Seelen WEG is disabled, or if native MenuHost dock/appbar code is reintroduced.
- Clicking Wi-Fi opens the custom MenuHost Network panel; the icon stays visually Wi-Fi so VPN/tunnel routes do not turn it into a misleading shield or generic computer glyph.
- Clicking Bluetooth opens the custom MenuHost Bluetooth panel.
- Battery is a right-side Mac-style system readout, merged with charging state, and opens the custom Control Center when clicked.
- Clicking the sliders control opens the custom Control Center with Wi-Fi/Bluetooth live tiles, display and sound sliders, System Settings, Show Desktop, Lock Screen, Sleep, Restart, and Shut Down.
- Bell and date/time currently call `macmakeover-notification-center:` to request the native Windows Notification Center rather than Seelen Flyouts. The 2026-07-10 second acceptance round reproduced an open issue where the native window became hidden while retaining foreground focus; treat this interaction as a release gate until visible-surface and subsequent app-focus tests pass.
- Normal sliders/Control Center clicks are handled by the sliders item's `onClick`, which opens `macmakeover-control-center:`. That protocol writes `control` into the resident `tools\MacMakeover.MenuHost` pipe and falls back to starting MenuHost with `--show control` if needed.
- Do not re-add Seelen's `@seelen/tb-quick-settings` item unless the user explicitly asks to restore the old flyout.
- `Alt+Space` opens Microsoft Command Palette / PowerToys-style search.
- Command Palette web search is disabled.
- Command Palette is trimmed to local Spotlight-like providers.
- PowerToys Run is enabled as a fallback.
- Windows Search has Bing/web search disabled through per-user registry values, with a best-effort managed policy write when allowed.

## Troubleshooting

If Seelen does not start:

```powershell
.\scripts\install-apps.ps1
.\scripts\verify.ps1
```

If the top bar is blank, check for YAML/schema errors:

```powershell
Get-Content "$env:LOCALAPPDATA\com.seelen.seelen-ui\logs\Seelen UI.log" -Tail 120 |
  Select-String -Pattern "SerdeYaml|error|failed|panic|fancy-toolbar" -CaseSensitive:$false
```

If app icons or dock pins do not launch, the executable paths probably differ on the new machine. Update Seelen dock pins through the UI, or edit:

```text
%APPDATA%\com.seelen.seelen-ui\data\seelen-weg\state.yml
```

The file is the portable pin source for the visible Seelen WEG dock. Keep `@seelen/weg.enabled` set to `true`. The experimental native `MacMakeover.MenuHost` dock/appbar path was removed because it caused maximize/work-area regressions.

If a previously maximized app is still sitting behind the dock after a restore/restart, make Windows recalculate that window against its monitor's current work area:

```powershell
.\scripts\fit-windows-to-workarea.ps1
```

That script is intentionally one-shot. Do not replace it with a background window mover; the always-running nudge approach caused unrelated maximize/navigation regressions.

If clicking the Apple mark opens a terminal, rerun:

```powershell
.\scripts\restore.ps1 -SkipSeelenRestart -SkipHotCorners -SkipSpotlightShortcuts
.\scripts\verify.ps1
```

`verify.ps1` prints the registered `macmakeover-apple-menu:` command and warns if it is not using the fast `conhost.exe --headless cmd /c echo apple> \\.\pipe\MacMakeover.MenuHost` launcher set up by `Install-AppleMenuHandler.ps1`. It also fails if the Seelen toolbar loses its item-owned Apple URI click.

If Alt+Tab appears to stop working while an Apple, Control Center, Network, or Bluetooth menu is open, rebuild/restart MenuHost:

```powershell
dotnet build .\tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release
Get-Process MacMakeover.MenuHost -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process .\tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe -WindowStyle Hidden
```

Current MenuHost popups close when Alt/system switching starts or when foreground ownership changes, so topmost menus do not linger over native Alt+Tab.

If the sliders control opens Seelen's old power/options screen, rerun:

```powershell
.\scripts\restore.ps1 -SkipSeelenRestart -SkipSpotlightShortcuts
.\scripts\Install-MacControlCenterHandler.ps1
.\scripts\install-hot-corners.ps1 -StartNow
.\scripts\verify.ps1
```

`verify.ps1` prints the registered `macmakeover-control-center:` command and warns if it is not using the fast MenuHost pipe launcher. It also fails if the Apple logo loses its item-owned URI handler and falls back to broad helper-owned pixel routing.

If wallpaper does not change on a managed device, check whether the organization enforces wallpaper through policy.

If Bing/web results still appear in Windows Start search after restore, the machine may require the managed policy value `DisableSearchBoxSuggestions=1` under `HKCU\Software\Policies\Microsoft\Windows\Explorer`, which can be blocked on managed devices. The normal user-level Search and SearchSettings values are still restored.

If a hot corner feels too eager, increase `dwellMilliseconds` or reduce `cornerSize` in `config\hot-corners.json`, then rerun:

```powershell
.\scripts\install-hot-corners.ps1 -StartNow
```

## Future Improvement Ideas

- Add an optional app-install profile for browsers/dev tools used by the dock pins.
- Make dock pin restoration path-aware instead of copying absolute paths.
- Add image diffing against known-good menu-bar and dock screenshots.
- Split remote-access setup into its own package if RustDesk/Tailscale setup grows.
- Add optional Everything integration for faster file search if needed later.
