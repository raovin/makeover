# Mac Makeover QA Test Matrix

Status date: 2026-07-10. `PASS` means directly evidenced in this audit; `OPEN` is not accepted; `STATIC` means configuration/source evidence only.

## Commands

Run from the repository root:

```powershell
git status --short
git log --oneline -20
.\scripts\verify.ps1
.\scripts\verify.ps1 -CaptureScreenshot
dotnet build .\tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release --nologo
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("scripts\verify.ps1", [ref]$null, [ref]$errors) | Out-Null
$errors
git diff --check
```

If a Seelen config/theme file changes, stop Seelen before the edit, restart through `\Seelen\Seelen UI Service`, inspect both Seelen logs, and rerun the complete matrix. The scoped implementation in this audit does not plan to change Seelen files.

## Static and regression checks

| ID | Check | Method | Pass criteria | Baseline |
|---|---|---|---|---|
| S-01 | Shortcuts/task switcher | Inspect live/repo JSON and `settings.json`; run verifier | shortcuts JSON is disabled and task switcher is false | PASS |
| S-02 | WEG and performance modes | Run verifier | WEG true; default/onBattery/onEnergySaver all Disabled | PASS |
| S-03 | Item-owned routes | Inspect toolbar/plugin; run verifier | Apple, Network, Bluetooth, Control use URI handlers; all helper broad zones false | PASS |
| S-04 | No old quick settings | Search toolbar and run verifier | no `@seelen/tb-quick-settings` | PASS |
| S-05 | MenuHost activation guard | Search/build | `WS_EX_NOACTIVATE` and `ShowWithoutActivation`; no `Activate`/`SetForegroundWindow` | PASS |
| S-06 | No native appbar/background mover | Search/run verifier | no DockForm/appbar APIs; no helper window nudge | PASS |
| S-07 | Repo/live drift | SHA-256 comparison and no-index diff | intentional drift documented; no unreviewed theme/toolbar drift | PASS with WEG risk |
| S-08 | Seelen logs | inspect latest 160 lines | no YAML panic/blank-toolbar error; file-path errors documented | PASS with Codex icon warning |

## Visual checks and exact screenshots

| ID | State | Screenshot(s) | Pass criteria | Baseline |
|---|---|---|---|---|
| V-01 | Full virtual desktop, maximized apps | `qa/visual-qa-20260710-121233/desktop.png` | both bars/docks present; no app content under dock | PASS |
| V-02 | Legacy top/bottom crops | final `qa/visual-qa-20260710-123039/top-130.png`, `bottom-240.png` | must describe the same intended monitor | PASS: exact hashes match primary monitor files |
| V-03 | Per-monitor full/top/bottom | `qa/visual-qa-20260710-123039/monitor-*-desktop.png`, `monitor-*-top-130.png`, `monitor-*-bottom-240.png` | every active monitor has all three crops | PASS: 1920x1200 primary and 1920x1080 secondary |
| V-04 | Apple menu | `qa/recovery-audit-20260710/baseline-apple-menu-open.png` | aligned rows, no clipping/ghost tooltip/terminal | PASS visually; wrong monitor |
| V-05 | Control Center | `qa/recovery-audit-20260710/baseline-control-center-open.png` | intended panel, aligned tiles/sliders/rows, no old Seelen flyout | PASS via protocol |
| V-06 | Network | `qa/recovery-audit-20260710/baseline-network-panel-open-pipe.png` | compact Network panel, readable connection state | PASS via pipe |
| V-07 | Bluetooth | `qa/recovery-audit-20260710/baseline-bluetooth-panel-open.png` | compact Bluetooth panel, readable state/actions | PASS via pipe |
| V-08 | Notification/calendar | `qa/recovery-audit-20260710/baseline-notification-calendar-open.png` | Windows surface visible, no custom panel beneath | FAIL/OPEN: surface not captured |
| V-09 | Minimized desktop | post-change `minimized-desktop.png` plus per-monitor crops | wallpaper, bars, docks correct with no app windows | OPEN |
| V-10 | Maximized common app | final per-monitor desktop/bottom crops | client bottom <= monitor work-area bottom; dock opaque | PASS for current Codex/Terminal windows; work-area dry run found no candidates |

Inspect every visual for overlap, clipping, vertical/text baseline alignment, icon spacing, badge placement, hairlines, dock opacity, active indicators, and accurate click affordances.

## Interaction checks

| ID | Interaction | Exact procedure | Pass criteria | Baseline |
|---|---|---|---|---|
| I-01 | Normal Alt+Tab | focus a normal app; press Alt+Tab | foreground app changes through native switcher | PASS during Apple dismissal sequence |
| I-02 | Apple actual click | click toolbar Apple item | Apple menu <= 500 ms, no visible terminal, one host | Baseline click PASS except wrong monitor; placement fix passed via pointer+pipe; actual-click recheck OPEN |
| I-03 | Apple then Alt+Tab | open via actual click; Alt+Tab | menu is absent after switch; switch completes | PASS; see `baseline-apple-alt-tab-dismissed.png` |
| I-04 | Control actual click | click sliders item | custom Control Center, not Seelen quick settings | OPEN; protocol path passed |
| I-05 | Control then Alt+Tab | open via actual click; Alt+Tab | popup closes and switch completes | OPEN due Windows automation activation failure |
| I-06 | Wi-Fi actual click | click toolbar network item | compact MenuHost Network panel | OPEN; handler/pipe passed |
| I-07 | Bluetooth actual click | click toolbar Bluetooth item | compact MenuHost Bluetooth panel | OPEN; handler/pipe passed |
| I-08 | Bell actual click | click bell | Windows notification surface, not Control Center | OPEN; static route only |
| I-09 | Date/time actual click | open custom panel, click date | Windows calendar/notification surface; custom panel closes with no stacking | OPEN |
| I-10 | Outside click | for each MenuHost panel, click a normal app | panel closes after grace period | Apple implicitly passed via switching; other panels OPEN |
| I-11 | Physical top corners | click exact top-left and top-right on each monitor | Show Desktop occurs once; nearby app chrome does not trigger | OPEN |
| I-12 | Restart Seelen | restart scheduled task, wait ready, verify | both toolbars/docks return and logs have no schema failure | PASS: both displays Ready; post-restart capture passed |
| I-13 | Maximize/restore apps | Chrome, Explorer, Terminal, and available tools | no client content behind dock/top bar | baseline Explorer/Terminal visual PASS; adversarial set OPEN |

## Performance checks

| ID | Measurement | Pass criteria | Baseline |
|---|---|---|---|
| P-01 | Control Center protocol to MenuHost `Shown` log | <= 500 ms warm | PASS: about 260 ms |
| P-02 | Network protocol to `Shown` | <= 750 ms warm | PASS: about 371 ms |
| P-03 | Bluetooth protocol to `Shown` | <= 750 ms warm | PASS: about 291 ms |
| P-04 | Apple actual click | visible within 500 ms | PASS by observation; exact poll unavailable |
| P-05 | Duplicate host | repeated Apple/Control open-close | exactly one same MenuHost PID | PASS: PID 38024 remained single |
| P-06 | Resource settling | repeated isolated and mixed open-close cycles | no continuing growth across repeated batches | FAIL: Control-only 10 cycles retained +68 handles after ten seconds; host restarted cleanly |
| P-07 | Hot-corner helper | process sample and config | one Windows PowerShell process; 25-40 ms polling; no visible flicker | STATIC PASS; physical clicks OPEN |
| P-08 | Telemetry/layout shifting | inspect consecutive top-bar captures | no flicker or horizontal shift | Not applicable: center telemetry is empty |

## Post-change acceptance gate

Do not call the recovery complete unless all `OPEN` interaction items required by the product are either directly passed or explicitly handed off for a user-observed run. A passing verifier and static source checks do not override a failed or unperformed interaction.

Final automated evidence passed for the bounded code changes, but the overall desktop remains partial acceptance because I-04 through I-11 (except baseline Apple), I-13's wider app set, V-08, V-09, and P-06 are not passing.
