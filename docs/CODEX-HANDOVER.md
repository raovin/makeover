# Handoff To Claude Code: Continue Beautifying The Windows macOS Makeover

Last updated: 2026-06-29 Europe/London by Codex.

You are taking over a Windows 11 desktop-customization project. The user wants this PC to feel more like macOS: a refined top menu bar, bottom dock, Apple-style top-left menu, Spotlight-like search, no Bing clutter, native Alt+Tab, and zero visible overlap/clipping.

The user is very explicit about quality: do not claim a visual task is finished without a real visual QA check. For any visual change, make the change, restart/reload the affected shell, capture screenshots, inspect them, and tell the user what you verified.

## Latest (2026-06-29, Codex Audit Fix)

- Normal Apple and Control Center clicks now open through `tools\MacMakeover.MenuHost`, a resident owner-drawn .NET WinForms host. This replaced the laggy PowerShell/WPF click path.
- The protocol handler must be `conhost.exe --headless` running `scripts\Show-MacAppleMenu.ps1` (registered by `scripts\Install-AppleMenuHandler.ps1`), because `wscript.exe` is blocked by this machine's Defender/ASR policy.
- Top-right sliders, charge-rate, and battery clicks open the custom MenuHost Control Center instead of Seelen's built-in quick-settings/power flyout. The `macmakeover-control-center:` protocol remains registered by `scripts\Install-MacControlCenterHandler.ps1` only as fallback plumbing.
- Performance correction: normal Apple and Control Center clicks are no longer launched by Seelen `onClick` URI handlers. `scripts\start-hot-corners.ps1` owns those top-bar click zones and sends `apple` / `control` over the `MacMakeover.MenuHost` named pipe. The resident host must be running so clicks do not cold-launch.
- `scripts\verify.ps1` is the gatekeeper: it fails if the live Apple-menu handler is missing, still points at `wscript.exe`, or is not registered to the conhost launcher.
- Top-left/top-right outer-corner clicks are handled by `scripts\start-hot-corners.ps1` and send Show Desktop. Do not re-enable Seelen's invisible `.ft-corner-button`; it stole clicks from the Apple glyph.
- The three previous locations were consolidated into this single git repo at `C:\Users\VineethRao\source\repos\mac-makeover`. The old brunel copy is kept untouched as a frozen backup.

## Current State In One Screenful

- Repo (single source of truth): `C:\Users\VineethRao\source\repos\mac-makeover` — a standalone git repo (default branch `main`, no remote yet).
- Frozen backup only: `C:\Users\VineethRao\source\repos\brunel\workspace\desktop\mac-makeover` (GitHub `raovin/brunel`). Do not edit; it is historical.
- Latest commit: run `git -C C:\Users\VineethRao\source\repos\mac-makeover log -1 --oneline`.
- Seelen config root: `C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui`
- Seelen local/log root: `C:\Users\VineethRao\AppData\Local\com.seelen.seelen-ui`
- Seelen package currently observed: `C:\Program Files\WindowsApps\Seelen.SeelenUI_2.7.3.0_x64__p6yyn03m1894e\seelen-ui.exe`
- Seelen autostart task: `\Seelen\Seelen UI Service`
- Primary display observed for QA: 1280x800

## User Preferences And Recent Corrections

- The top-left Apple icon should behave like macOS: it should open a compact Apple menu directly, not a big Seelen user drawer and not a terminal.
- The top-right network, sliders, and power/battery widgets should open the custom Control Center directly, not Seelen's old power/options screen.
- The dock should stay rich; the user previously said there is no need to trim it.
- The top bar should read like a Mac menu bar: Apple mark at far left, focused app identity next to it, centered clock, status widgets on the right.
- No visible overlap, clipped text, ghost tooltips, ugly separator lines, or accidental title pollution such as `Windows PowerShell / Apple Menu`.
- Alt+Tab should remain native Windows Alt+Tab. Do not revive Seelen task-switcher shortcuts.
- Lock-screen PIN entry previously broke during shortcut/task-switcher experiments. Keep Seelen shortcuts disabled.
- TeamViewer is being phased out; do not spend time on it unless asked.

## Critical Guardrails

1. Keep Seelen shortcuts disabled:

```json
{"enabled":false,"shortcuts":{}}
```

Live file:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\settings_shortcuts.json
```

2. Stop Seelen before editing Seelen config/theme files. Seelen can overwrite disk edits from memory.

3. Do not force-restart `explorer.exe` while Seelen is running. That previously caused rendering weirdness.

4. Do not disable or bypass Windows Security. Read-only inspection is fine.

5. The toolbar YAML is schema-sensitive. Bad YAML can blank the whole bar with a `SerdeYaml` error.

6. Do not register the Apple menu protocol directly to PowerShell. That caused a visible terminal window.

Correct handler shape (registered by `scripts\Install-AppleMenuHandler.ps1`):

```text
"C:\Windows\System32\conhost.exe" --headless "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Users\VineethRao\source\repos\mac-makeover\scripts\Show-MacAppleMenu.ps1" "%1"
```

Note: `wscript.exe`/VBS launchers are blocked on this machine (Defender/ASR throws "Windows Script Host failed - not enough memory resources"). They are intentionally not packaged; do not recreate or register one.

Registry path:

```text
HKCU:\Software\Classes\macmakeover-apple-menu\shell\open\command
```

7. Do not wire Seelen toolbar `onClick` directly to `macmakeover-apple-menu:` or `macmakeover-control-center:`. That URI/ShellExecute path caused multi-second perceived lag. Normal Apple and Control Center clicks must be owned by `scripts\start-hot-corners.ps1`, which sends named-pipe commands to the resident `tools\MacMakeover.MenuHost` process. The URI protocols remain registered only as fallback/restore plumbing.

8. Do not re-add Seelen's `@seelen/tb-quick-settings` unless the user explicitly asks for the old Seelen flyout back. The right-side Control Center entry is custom and is backed by the hot-corners top-bar click router.

Correct Control Center handler shape (registered by `scripts\Install-MacControlCenterHandler.ps1`):

```text
"C:\Windows\System32\conhost.exe" --headless "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Users\VineethRao\source\repos\mac-makeover\scripts\Show-MacControlCenter.ps1" "%1"
```

Registry path:

```text
HKCU:\Software\Classes\macmakeover-control-center\shell\open\command
```

9. Treat delayed UI automations as reliability-critical. Do not chain one delayed UI task through another delayed UI task. After creating/updating an automation, verify the saved automation state and report id, status, schedule, target thread, and prompt summary. If the platform only permits one active heartbeat, say so and ask whether to replace it, create a separate thread/job, or do the work now. A delayed UI task is not complete until the requested action produces a visible success/failure report in the thread.

## Apple Menu: What Changed

The old top-left Apple glyph was Seelen's built-in `@seelen/tb-user-menu`, styled to look like an Apple logo. Clicking it opened a large Seelen user menu with profile/folders.

Old top-left Apple click screenshot:

```text
C:\tmp\mac-apple-old-top-left-click.png
```

The current top-left Apple glyph is a custom toolbar item:

```yaml
- id: macmakeover-apple-menu
  template: 'return "Apple";'
  tooltip: 'return "";'
  onClick: null
  style: {width: 30, minWidth: 30, maxWidth: 30, flexShrink: 0}
```

Live toolbar file:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\data\seelen-fancy-toolbar\state.yml
```

Normal clicks are caught by `scripts\start-hot-corners.ps1` and shown by `tools\MacMakeover.MenuHost`. The fallback URI launches this WPF menu script via `conhost.exe --headless` (registered by `scripts\Install-AppleMenuHandler.ps1`):

```text
C:\Users\VineethRao\source\repos\mac-makeover\scripts\Show-MacAppleMenu.ps1
```

There is no legacy VBS wrapper in the chain; `wscript.exe` is blocked by this machine's Defender/ASR policy.

Current Apple menu includes:

- About This Mac
- System Settings...
- App Store
- Recent Items
- Force Quit...
- Sleep
- Restart...
- Shut Down...
- Lock Screen
- Log Out Vineeth Rao...

Restart, Shut Down, and Log Out prompt before acting.

Current fixed Apple-click screenshot:

```text
C:\tmp\mac-apple-restored-after-reconstruction.png
```

Earlier proof screenshot after polish:

```text
C:\tmp\mac-apple-menu-final-polished.png
```

## Control Center / Power Popover

The old top-right power/settings entry used Seelen's built-in `@seelen/tb-quick-settings`, which opened the clunky power/options screen. That item has been removed from:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\data\seelen-fancy-toolbar\state.yml
```

The replacement is a custom toolbar item plus click handlers on the charge-rate and battery widgets:

```yaml
- id: macmakeover-control-center
  template: 'return icon("LuSlidersHorizontal");'
  tooltip: 'return "";'
  onClick: null
```

Normal clicks are caught by `scripts\start-hot-corners.ps1` and shown by `tools\MacMakeover.MenuHost`. The fallback URI launches this WPF script through `conhost.exe --headless`:

```text
C:\Users\VineethRao\source\repos\mac-makeover\scripts\Show-MacControlCenter.ps1
```

The current Control Center includes:

- Power & Battery Settings
- Network Settings
- System Settings
- Show Desktop
- Lock Screen
- Sleep
- Restart...
- Shut Down...

Because Seelen/Windows URI launches were measured as laggy, `scripts\start-hot-corners.ps1` routes the Apple zone, far-right control zone, and power/battery zone directly to the resident MenuHost. Keep that layer unless replacing the whole top-bar interaction model.

Recent visual/performance proof screenshots:

```text
C:\Users\VineethRao\source\repos\mac-makeover\qa\live-apple-click-200ms-poll30.png
C:\Users\VineethRao\source\repos\mac-makeover\qa\live-control-right-click-250ms.png
C:\Users\VineethRao\source\repos\mac-makeover\qa\live-control-power-zone-after-seelen-restart.png
C:\Users\VineethRao\source\repos\mac-makeover\qa\alt-tab-sanity.png
```

## Current Top Bar And Dock Files

Seelen toolbar state:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\data\seelen-fancy-toolbar\state.yml
```

Toolbar CSS:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\themes\macos-glass\styles\fancy-toolbar.css
```

Dock state:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\data\seelen-weg\state.yml
```

Dock CSS:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\themes\macos-glass\styles\weg.css
```

The toolbar CSS also collapses Seelen's invisible `.ft-corner-button`, because it stole clicks from the Apple glyph. Top-corner show-desktop clicks are now handled by the hot-corners helper instead.

## Safe Edit Cycle

Use this for Seelen edits:

```powershell
Get-Process | Where-Object { $_.ProcessName -match 'seelen|slu' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Edit files here.

Start-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service'
Start-Sleep -Seconds 10
Get-Process | Where-Object { $_.ProcessName -match 'seelen|slu' } |
  Select-Object ProcessName,Id,Responding,StartTime
```

Check Seelen logs after every config/theme edit:

```powershell
Get-Content -LiteralPath "$env:LOCALAPPDATA\com.seelen.seelen-ui\logs\Seelen UI.log" -Tail 160 |
  Select-String -Pattern 'SerdeYaml|error|failed|panic|Ready|fancy-toolbar|weg' -CaseSensitive:$false
```

Run the verifier:

```powershell
cd C:\Users\VineethRao\source\repos\mac-makeover
.\scripts\verify.ps1 -CaptureScreenshot
```

That captures full/top/bottom screenshots under:

```text
C:\Users\VineethRao\source\repos\mac-makeover\qa
```

The verifier uses FFmpeg with `-draw_mouse 0` so the custom cursor does not create black-box capture artifacts.

## Search / Spotlight State

- `Alt+Space` opens Microsoft Command Palette / PowerToys-style local search.
- Windows Search Bing/web results are disabled via per-user registry values.
- Command Palette web search provider is disabled.
- PowerToys Run remains enabled as a fallback.

Do not re-route `Alt+Space` through Seelen.

## Hot Corners

Hot corners are managed by:

```text
C:\Users\VineethRao\source\repos\mac-makeover\scripts\start-hot-corners.ps1
```

Config:

```text
C:\Users\VineethRao\source\repos\mac-makeover\config\hot-corners.json
```

The top-left hot corner and Apple glyph are close together. Top-left/top-right outer-corner clicks use `clickCornerSize` from `config\hot-corners.json` and send Show Desktop. Be careful when changing hit targets; do not reintroduce invisible click stealing.

The same helper owns the Apple click zone through `appleMenuClickEnabled` and `appleMenuZone*`, plus the top-right Control Center/power hit zones through `controlCenterClickEnabled`, `controlCenterRightButtonWidth`, and the `controlCenterPowerZone*` offsets. The exact physical top-left/top-right corners remain reserved for Show Desktop.

## The Repo / Git Backup

This standalone repo is both the live config home and the restoreable Git-backed package:

```text
C:\Users\VineethRao\source\repos\mac-makeover
```

It includes:

- Seelen config snapshot
- PowerToys / Command Palette settings
- Hot corners config and scripts
- Apple menu scripts
- Control Center / power popover scripts
- Restore and verify scripts
- README and Claude entry point

If you make a lasting visual/setup change, update the live config, mirror it into this repo, then commit from the repo root:

```powershell
git -C C:\Users\VineethRao\source\repos\mac-makeover status --short
git -C C:\Users\VineethRao\source\repos\mac-makeover diff
git -C C:\Users\VineethRao\source\repos\mac-makeover add .
git -C C:\Users\VineethRao\source\repos\mac-makeover commit -m "Update mac makeover polish"
```

There is no remote yet, so there is nothing to push.

## Beautification Ideas For Claude

Start with visual QA before changing anything. Then pick one small, visible improvement at a time.

Top picks:

1. Apple menu polish
   - Make the menu feel closer to macOS: lighter blur/glass, subtler border, tighter row rhythm, cleaner separators.
   - Consider restoring access to Seelen folders/settings as a submenu or secondary item, because the old Apple click exposed useful folders.
   - Keep the no-terminal hidden launcher intact.

2. Top bar polish
   - Make the focused app label more Mac-like: app name only, no noisy title unless useful.
   - Keep the clock visually centered even when right-side metrics widen.
   - Ensure long app names do not overlap the center clock.
   - Keep right-side status readable but less dense if numbers expand.
   - Preserve the custom Control Center; do not fall back to Seelen's quick-settings flyout.

3. Dock polish
   - Keep current app set; user said no need to trim.
   - Improve active indicators, hover scale, spacing, and glass contrast if the current dock feels busy.
   - Verify at the bottom crop after every change.

4. Spotlight polish
   - Keep Bing/web results out.
   - If available, consider Everything integration later for faster file search.
   - Verify `Alt+Space` still opens cleanly and is not intercepted by Seelen.

5. QA harness
   - Add image comparison or a scripted visual checklist for top bar, dock, Apple menu, and Spotlight.
   - Keep screenshots in ignored QA folders; do not commit bulky transient captures unless explicitly wanted.

Quality polish:

- Use real screenshots as the source of truth.
- Capture top strip, bottom dock strip, and Apple-menu-open state.
- Check actual clicks, not only direct script launches.
- Watch for title pollution in the top bar after opening the Apple menu.
- Watch for ghost tooltips through translucent panels.
- Confirm no terminal/pwsh window flashes.
- Confirm `settings_shortcuts.json` remains disabled.

## Known QA Images

Current custom Apple menu after restoration:

```text
C:\tmp\mac-apple-restored-after-reconstruction.png
```

Old Seelen user menu from top-left Apple click:

```text
C:\tmp\mac-apple-old-top-left-click.png
```

Final polished Apple menu from the prior Codex pass:

```text
C:\tmp\mac-apple-menu-final-polished.png
```

Recent normal top/dock QA crops:

```text
C:\Users\VineethRao\source\repos\mac-makeover\qa\visual-qa-20260627-230031\top-130.png
C:\Users\VineethRao\source\repos\mac-makeover\qa\visual-qa-20260627-230031\bottom-240.png
```

## Definition Of Done

For any beautification iteration:

- Implement one focused change.
- Restart/reload what needs restarting.
- Run log/config checks.
- Capture and inspect screenshots.
- If behavior is clickable, test the actual click path.
- Mirror any lasting change from the live config into this repo so it survives a restore.
- Commit changes from the repo root when appropriate (no remote yet, so no push).
- Tell the user exactly what changed and what visual QA passed.
