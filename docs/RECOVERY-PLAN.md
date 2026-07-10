# Mac Makeover Recovery Plan

Decision: simplify the current Seelen + MenuHost architecture. Baseline commit: `6819380`.

Execution status: Tasks 1-3 passed. Task 4 is partial because Windows UI automation stopped activating windows after the shell interaction test. Task 5 remains a separate follow-up.

## Ordered tasks

### 1. Freeze and record the baseline

- Files changed: the four recovery documents only.
- Proves: branch/dirty state, live component inventory, display topology, baseline verifier result, and known gaps are explicit.
- Rollback point: `6819380` plus local QA screenshots under `qa/`.
- Stop if: the repo is not the stated source of truth or unrelated user changes appear.

### 2. Make MenuHost popup placement monitor-aware

- Expected file: `tools/MacMakeover.MenuHost/Program.cs`.
- Change: capture the screen under the pointer before the form handle is created and anchor Apple/Control/Network/Bluetooth to that screen instead of `Screen.PrimaryScreen`.
- Proves: a toolbar action on a secondary monitor produces a nearby popup and uses that monitor's DPI.
- Verification: Release build; restart only MenuHost; place pointer on each monitor; issue a panel command; inspect log device/bounds and screenshots; repeat Apple/Control open-close; confirm one host PID and no activation.
- Rollback: restore `Program.cs`, rebuild Release, restart MenuHost.
- Stop if: panel size is wrong at mixed DPI, popup enters Alt+Tab, no-activate behavior changes, or a panel fails to paint.

### 3. Make visual QA per-monitor and DPI-aware

- Expected file: `scripts/verify.ps1`.
- Change: set per-monitor DPI awareness before screen enumeration; capture the entire virtual desktop in both FFmpeg and fallback paths; keep the full screenshot; make legacy top/bottom crops describe the primary monitor; emit full/top/bottom files for every active monitor with luminance/status output.
- Proves: stacked or offset displays cannot create misleading global-edge crops.
- Verification: PowerShell parser check; run verifier with and without screenshots; confirm dimensions/paths for both monitors; inspect every generated image.
- Rollback: restore `verify.ps1`; delete only the new transient QA folder if desired.
- Stop if: fallback/FFmpeg capture fails, rectangles exceed the virtual bitmap, single-monitor behavior regresses, or legacy output names disappear.

### 4. Rerun adversarial functional QA

- Expected repo changes: none unless a failing gate justifies a separate reviewed fix.
- Proves: fixes survive interaction, process, work-area, and restart checks.
- Sequence: Apple repeated open/close; Apple to Alt+Tab; Control repeated open/close; Control to Alt+Tab; Network/Bluetooth/bell/date in alternating order; outside click; both top corners; maximize/restore common apps; show desktop; restart Seelen; run verifier again.
- Rollback: if a runtime regression follows Task 2, use its rollback before continuing.
- Stop if: native switching or lock-screen safety is uncertain. Do not experiment with lock-screen input automatically; rely on disabled-shortcut static guard plus a user-observed lock test when required.

### 5. Follow-up simplification (separate change set)

- Expected files: `scripts/start-hot-corners.ps1`, protocol installer scripts, notification action, README/handover, and possibly MenuHost.
- Remove only after replacement tests exist: dormant broad pixel-zone functions, unused WPF warm-runspace fallback paths, duplicated handler registration code, and stale architecture claims.
- Move Network/Bluetooth state collection off the MenuHost UI thread and make timeouts real.
- Add an explicit `close` before notification/calendar activation if direct interaction testing confirms stacking.
- Replace version-specific dock executable paths with UMID/path-aware restoration.
- Stop if: simplification weakens self-healing startup or restore portability.

Highest-priority follow-up is the Control Center resource-retention failure: isolate timer, form, background state-enrichment, child-process, and Core Audio COM lifetimes with a longer soak/profiler run before changing cleanup behavior.

## Required evidence bundle

- Pre-change: `qa/visual-qa-20260710-121233/` and `qa/recovery-audit-20260710/baseline-*`.
- Post-change: `qa/visual-qa-20260710-123039/`, containing the virtual desktop, legacy primary crops, and both monitors' full/top/bottom images after Seelen restart.
- Interaction screenshots: Apple, Control Center, Network, Bluetooth, notification/calendar, minimized desktop, maximized app, and post-Alt+Tab dismissal.
- Text evidence: verifier output, Release build output, parser result, Seelen log health, MenuHost process/resource sample, `git diff --check`, and final `git status --short`.

## Completion policy

Commit only the coherent recovery change set. Local QA screenshots are transient/ignored unless explicitly requested for source control. If direct interaction coverage remains blocked, commit the audit and bounded fixes only if their own verification passes, and leave the overall product acceptance state as partial.

The bounded fixes passed their build/parser/verifier/visual/restart gates. The open physical interaction and performance items remain explicit release gates rather than blockers to retaining these two independently verified improvements.
