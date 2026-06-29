# Handoff To Claude Code: Continue Beautifying The Windows macOS Makeover

Last updated: 2026-06-28 23:44 Europe/London by Codex.

You are taking over a Windows 11 desktop-customization project. The user wants this PC to feel more like macOS: a refined top menu bar, bottom dock, Apple-style top-left menu, Spotlight-like search, no Bing clutter, native Alt+Tab, and zero visible overlap/clipping.

The user is very explicit about quality: do not claim a visual task is finished without a real visual QA check. For any visual change, make the change, restart/reload the affected shell, capture screenshots, inspect them, and tell the user what you verified.

## Latest (2026-06-29, Claude)

- Apple menu visually rebuilt to authentic macOS proportions: 244px width, `SizeToContent` so the panel hugs its rows, a top-to-bottom gradient, 9px rounded corners, and a drop shadow.
- The protocol handler was moved off `wscript.exe` onto `conhost.exe --headless` running `scripts\Show-MacAppleMenu.ps1` (registered by `scripts\Install-AppleMenuHandler.ps1`), because `wscript.exe` is blocked by this machine's Defender/ASR policy.
- The three previous locations were consolidated into this single git repo at `C:\Users\VineethRao\source\repos\mac-makeover`. The old brunel copy is kept untouched as a frozen backup.

## Current State In One Screenful

- Repo (single source of truth): `C:\Users\VineethRao\source\repos\mac-makeover` — a standalone git repo (default branch `main`, no remote yet).
- Frozen backup only: `C:\Users\VineethRao\source\repos\brunel\workspace\desktop\mac-makeover` (GitHub `raovin/brunel`). Do not edit; it is historical.
- Latest relevant commit: `a282446 Fix mac makeover Apple menu launcher`
- Seelen config root: `C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui`
- Seelen local/log root: `C:\Users\VineethRao\AppData\Local\com.seelen.seelen-ui`
- Seelen package currently observed: `C:\Program Files\WindowsApps\Seelen.SeelenUI_2.7.3.0_x64__p6yyn03m1894e\seelen-ui.exe`
- Seelen autostart task: `\Seelen\Seelen UI Service`
- Primary display observed for QA: 1280x800

## User Preferences And Recent Corrections

- The top-left Apple icon should behave like macOS: it should open a compact Apple menu directly, not a big Seelen user drawer and not a terminal.
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

Note: the old `wscript.exe` -> `Launch-MacAppleMenu.vbs` launcher is blocked on this machine (Defender/ASR throws "Windows Script Host failed - not enough memory resources"). The `.vbs` remains only as dead legacy; do not register it.

Registry path:

```text
HKCU:\Software\Classes\macmakeover-apple-menu\shell\open\command
```

7. Treat delayed UI automations as reliability-critical. Do not chain one delayed UI task through another delayed UI task. After creating/updating an automation, verify the saved automation state and report id, status, schedule, target thread, and prompt summary. If the platform only permits one active heartbeat, say so and ask whether to replace it, create a separate thread/job, or do the work now. A delayed UI task is not complete until the requested action produces a visible success/failure report in the thread.

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
  onClick: 'open("macmakeover-apple-menu:")'
  style: {width: 30, minWidth: 30, maxWidth: 30, flexShrink: 0}
```

Live toolbar file:

```text
C:\Users\VineethRao\AppData\Roaming\com.seelen.seelen-ui\data\seelen-fancy-toolbar\state.yml
```

The URI launches this WPF menu script via `conhost.exe --headless` (registered by `scripts\Install-AppleMenuHandler.ps1`):

```text
C:\Users\VineethRao\source\repos\mac-makeover\scripts\Show-MacAppleMenu.ps1
```

The legacy `scripts\Launch-MacAppleMenu.vbs` wrapper is no longer in the chain; `wscript.exe` is blocked by this machine's Defender/ASR policy.

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

The toolbar CSS also collapses Seelen's invisible `.ft-corner-button`, because it stole clicks from the Apple glyph and triggered show-desktop behavior.

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

The top-left hot corner and Apple glyph are close together. Be careful when changing hit targets; do not reintroduce invisible click stealing.

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
