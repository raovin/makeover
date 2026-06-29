# mac-makeover

Portable backup and restore package for the Windows 11 macOS-style desktop setup.

This repo is the single home and source of truth for the macOS makeover, so a new Windows machine can be rebuilt from here instead of relying on the old machine as the migration source. A frozen historical copy still lives under `brunel\workspace\desktop\mac-makeover`, but that is a backup only and is no longer the working location. This repo captures the repeatable parts of the setup: Seelen UI layout/theme, dock and menu-bar configuration, wallpaper assets, cursor assets, user-level appearance exports, and restore scripts.

Keep this repo private unless you have reviewed the app paths and registry exports. No credentials are intentionally stored here, but the package does include local app names, install paths, appearance settings, and dock pins.

## What You Get

- A macOS-style top menu bar using Seelen UI.
- A bottom dock using Seelen WEG.
- The custom `macos-glass` theme for the frosted menu bar and dock.
- The current toolbar layout: Apple-style mark, focused app, centered clock, and right-side status widgets.
- A Mac-style Apple menu on the top-left Apple mark, opened by the warmed hot-corners helper so it appears quickly and no terminal window appears.
- A custom Mac-style Control Center / power popover from the top-right sliders icon and power/battery widgets, replacing Seelen's built-in quick-settings flyout and avoiding slow URI launches.
- Seelen shortcuts disabled so native Windows Alt+Tab and lock-screen input remain normal.
- Spotlight-style search through PowerToys / Command Palette on `Alt+Space`.
- Windows Search web/Bing result suppression for the current user.
- macOS-style hot corners:
  - top-left/top-right outer-corner click: show desktop
  - bottom-left: show desktop
  - bottom-right: lock screen
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
  registry/               # User-level appearance registry exports
  scripts/
    backup-current.ps1    # Refresh this package from the current machine
    install-apps.ps1      # Install Seelen, optionally RustDesk/Tailscale
    install-hot-corners.ps1
    install-spotlight-shortcuts.ps1
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
    MacMakeover.MenuHost/  # Resident owner-drawn Apple/Control Center menu host
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

Supported hover and click actions are `Spotlight`, `TaskView`, `ShowDesktop`, `Lock`, `Sleep`, `ClipboardHistory`, and `None`. Click actions use the smaller `clickCornerSize` zones, so top-left/top-right show-desktop clicks do not steal the normal Apple icon or right-side menu-bar clicks.

The same helper also routes Apple, the top-right sliders icon, and the power/battery widgets to the resident .NET MenuHost over a named pipe. This avoids Seelen `onClick` URI/ShellExecute launches, which were measured as visibly laggy. The `macmakeover-apple-menu:` and `macmakeover-control-center:` protocol handlers remain registered as fallback/restore plumbing only.

## Manual Steps After Restore

Some setup must remain manual because it is account/device-specific:

- Sign into Tailscale.
- Sign into or configure RustDesk on the new device.
- Grant any remote-control permissions required by the OS.
- Approve installer or UAC prompts yourself.
- Confirm Seelen starts at login.
- Check dock pins whose app paths differ on the new machine.
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

There is no remote configured yet, so there is nothing to push. If you later add one, `git push` after committing.

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
- Normal Apple clicks are handled by `scripts\start-hot-corners.ps1`, which sends `apple` to `tools\MacMakeover.MenuHost`. The `macmakeover-apple-menu:` protocol remains registered through `conhost.exe --headless` running `scripts\Show-MacAppleMenu.ps1` as fallback. Registering it directly to a visible PowerShell window can show a terminal. `wscript.exe`/VBS launchers are blocked by this machine's Defender/ASR policy and are intentionally not packaged.
- `scripts\install-hot-corners.ps1` starts the helper and resident MenuHost. `verify.ps1` fails if the host is missing/not running or if the helper is running under `pwsh.exe`.
- Clicking the top-right sliders icon, charge-rate text, or battery widget opens the custom Control Center for Power & Battery Settings, System Settings, Show Desktop, Lock Screen, Sleep, Restart, and Shut Down.
- Normal Control Center clicks are handled by `scripts\start-hot-corners.ps1`, which sends `control` to `tools\MacMakeover.MenuHost`. The `macmakeover-control-center:` protocol remains registered through `conhost.exe --headless` running `scripts\Show-MacControlCenter.ps1` as fallback.
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

If clicking the Apple mark opens a terminal, rerun:

```powershell
.\scripts\restore.ps1 -SkipSeelenRestart -SkipHotCorners -SkipSpotlightShortcuts
.\scripts\verify.ps1
```

`verify.ps1` prints the registered `macmakeover-apple-menu:` command and warns if it is not using the `conhost.exe --headless` launcher set up by `Install-AppleMenuHandler.ps1`. It also fails if the Seelen toolbar is wired directly to the URI handler instead of the resident MenuHost path.

If the top-right sliders icon or power/battery widget opens Seelen's old power/options screen, rerun:

```powershell
.\scripts\restore.ps1 -SkipSeelenRestart -SkipSpotlightShortcuts
.\scripts\install-hot-corners.ps1 -StartNow
.\scripts\verify.ps1
```

`verify.ps1` prints the registered `macmakeover-control-center:` command and warns if it is not using the hidden Control Center launcher. It also fails if the Seelen toolbar is wired directly to the URI handler instead of the resident MenuHost path.

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
