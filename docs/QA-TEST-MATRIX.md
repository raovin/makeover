# Mac Makeover QA Test Matrix

Status date: 2026-07-10. `PASS` means directly evidenced in this audit; `OPEN` is not accepted; `STATIC` means configuration/source evidence only. The 14:00-14:18 recovery run applied the image-generated redesign to the live desktop and retested Snipping Tool, native Alt+Tab, Control Center dismissal, notification count layout, maximized work areas, both monitors, and panel churn.

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

If a Seelen config/theme file changes, stop Seelen before the edit, restart it, inspect both Seelen logs, and rerun the complete matrix. This recovery changed the toolbar state, toolbar/dock themes, WEG sizing, and three stale versioned pin paths; Seelen was stopped for the live copy, restarted, and both monitors returned `Ready`.

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
| V-01 | Full virtual desktop, maximized apps | `qa/visual-qa-20260710-140026/desktop.png` | both bars/docks present; no app content under dock | PASS after redesign |
| V-02 | Legacy top/bottom crops | final `qa/visual-qa-20260710-123039/top-130.png`, `bottom-240.png` | must describe the same intended monitor | PASS: exact hashes match primary monitor files |
| V-03 | Per-monitor full/top/bottom | `qa/visual-qa-20260710-140026/monitor-*-desktop.png`, `monitor-*-top-130.png`, `monitor-*-bottom-240.png` | every active monitor has all three crops | PASS: 1920x1200 primary and 1920x1080 secondary |
| V-04 | Apple menu | `qa/recovery-audit-20260710/baseline-apple-menu-open.png` | aligned rows, no clipping/ghost tooltip/terminal | PASS visually; wrong monitor |
| V-05 | Control Center | `qa/recovery-audit-20260710/baseline-control-center-open.png` | intended panel, aligned tiles/sliders/rows, no old Seelen flyout | PASS via protocol |
| V-06 | Network | `qa/recovery-audit-20260710/baseline-network-panel-open-pipe.png` | compact Network panel, readable connection state | PASS via pipe |
| V-07 | Bluetooth | `qa/recovery-audit-20260710/baseline-bluetooth-panel-open.png` | compact Bluetooth panel, readable state/actions | PASS via pipe |
| V-08 | Notification/calendar | `qa/recovery-audit-20260710/baseline-notification-calendar-open.png` | Windows surface visible, no custom panel beneath | FAIL/OPEN: surface not captured |
| V-09 | Minimized desktop | post-change `minimized-desktop.png` plus per-monitor crops | wallpaper, bars, docks correct with no app windows | OPEN |
| V-10 | Maximized common app | direct File Explorer maximize/restore plus final per-monitor crops | client bottom <= monitor work-area bottom; dock opaque | PASS: Explorer used y=31..742 on the 800-logical-pixel primary display, leaving the dock reservation intact; dry run found no repair candidates |
| V-11 | Notification count | primary and secondary 28 px toolbar captures plus `qa/visual-qa-20260710-140026/monitor-*-top-130.png` | count fully visible with no y=0 badge overflow | PASS: count `15` renders inline beside the DND glyph inside a bounded target |

Inspect every visual for overlap, clipping, vertical/text baseline alignment, icon spacing, badge placement, hairlines, dock opacity, active indicators, and accurate click affordances.

## Interaction checks

| ID | Interaction | Exact procedure | Pass criteria | Baseline |
|---|---|---|---|---|
| I-01 | Normal Alt+Tab | focus Rider; press Alt+Tab | foreground app changes through native switcher | PASS: focused-app label changed to Snipping Tool/Finder during repeated runs |
| I-02 | Apple actual click | click toolbar Apple item | Apple menu <= 500 ms, no visible terminal, one host | Baseline click PASS except wrong monitor; placement fix passed via pointer+pipe; actual-click recheck OPEN |
| I-03 | Apple then Alt+Tab | open Apple panel; Alt+Tab | menu is absent after switch; switch completes | PASS: MenuHost logged `Closing Apple Menu: Alt/system switcher detected` |
| I-04 | Control actual click | click sliders item | custom Control Center, not Seelen quick settings | OPEN; protocol path passed |
| I-05 | Control then Alt+Tab | open Control Center; Alt+Tab | popup closes and switch completes | PASS: final host logged foreground/system-switch dismissal and no post-fix thread exception |
| I-06 | Wi-Fi actual click | click toolbar network item | compact MenuHost Network panel | OPEN; handler/pipe passed |
| I-07 | Bluetooth actual click | click toolbar Bluetooth item | compact MenuHost Bluetooth panel | OPEN; handler/pipe passed |
| I-08 | Bell actual click | click bell | Windows notification surface, not Control Center | OPEN; static route only |
| I-09 | Date/time actual click | open custom panel, click date | Windows calendar/notification surface; custom panel closes with no stacking | OPEN |
| I-10 | Outside click | for each MenuHost panel, click a normal app | panel closes after grace period | Apple implicitly passed via switching; other panels OPEN |
| I-11 | Physical top corners | click exact top-left and top-right on each monitor | Show Desktop occurs once; nearby app chrome does not trigger | OPEN |
| I-12 | Restart Seelen | restart scheduled task, wait ready, verify | both toolbars/docks return and logs have no schema failure | PASS: both displays Ready; post-restart capture passed |
| I-13 | Maximize/restore apps | Chrome, Explorer, Terminal, and available tools | no client content behind dock/top bar | Explorer direct maximize/restore PASS; wider app set remains OPEN |
| I-14 | Snipping Tool New | activate Snipping Tool and invoke `New screenshot` | editor hides and capture overlay starts; overlay can be dismissed without a stuck custom panel | PASS: app reported zero visible editor windows in capture mode; capture overlay appeared in `visual-qa-20260710-135941`; Escape/app activation returned to a clean desktop |

## Performance checks

| ID | Measurement | Pass criteria | Baseline |
|---|---|---|---|
| P-01 | Control Center protocol to MenuHost `Shown` log | <= 500 ms warm | PASS: about 260 ms |
| P-02 | Network protocol to `Shown` | <= 750 ms warm | PASS: about 371 ms |
| P-03 | Bluetooth protocol to `Shown` | <= 750 ms warm | PASS: about 291 ms |
| P-04 | Apple actual click | visible within 500 ms | PASS by observation; exact poll unavailable |
| P-05 | Duplicate host | repeated Apple/Control open-close | exactly one same MenuHost PID | PASS: PID 38024 remained single |
| P-06 | Resource settling | repeated Control Center open-close batches | no continuing growth across repeated warm batches; no orphan probes | PASS after fix: real cancellable process timeout added; final warm confirmation batch settled at +4 handles and no child probes, versus the pre-fix +89 handles with a live PowerShell child |
| P-09 | Probe cancellation | churn Control Center faster than Wi-Fi/Bluetooth/brightness probes can finish | closing a form cancels and kills only its probe tree; no thread exception | PASS after idempotent disposal correction and final Alt+Tab run |
| P-07 | Hot-corner helper | process sample and config | one Windows PowerShell process; 25-40 ms polling; no visible flicker | STATIC PASS; physical clicks OPEN |
| P-08 | Telemetry/layout shifting | inspect consecutive top-bar captures | no flicker or horizontal shift | Not applicable: center telemetry is empty |

## Post-change acceptance gate

Do not call the recovery complete unless all `OPEN` interaction items required by the product are either directly passed or explicitly handed off for a user-observed run. A passing verifier and static source checks do not override a failed or unperformed interaction.

The reported blocking regressions are now directly covered: I-01/I-03/I-05/I-14, V-10/V-11, and P-06/P-09 pass. Overall acceptance is still partial for the remaining physical-click cases (I-04, I-06 through I-11), V-08/V-09, and I-13's wider app set.
