# Mac Makeover Recovery Audit Spec

Status: recovery baseline, redesign implementation, and post-change verification recorded on 2026-07-10 (Europe/London). Real-use reports subsequently exposed two critical input defects: negative-coordinate application clicks could fire Show Desktop, and Seelen's primary DPI-scaled toolbar rendered full width while Windows exposed only a 15x15 hit target. The Show Desktop defect was directly corrected and retested in Bruno. The toolbar now has a guarded 19px fallback router that engages only when `WindowFromPoint` proves the Seelen toolbar did not receive the click. A second acceptance round at 19:39-20:00 passed Bruno, Alt+Tab, restart, work-area, visual, build, parser, and popup performance checks, but proved that the bell path can leave a hidden Notification Center window owning foreground focus. Overall acceptance remains partial until that native notification failure and the primary-display fallback receive user-observed passes.

Baseline: `main` at `6819380`; the worktree was clean and matched `origin/main` before this audit began.

## Problem statement

`mac-makeover` has accumulated several generations of shell integration around Seelen UI, PowerToys, PowerShell helpers, protocol handlers, and a resident WinForms MenuHost. The current desktop is substantially functional, but prior fixes were accepted without a repeatable multi-state and multi-monitor evidence set. This makes regressions in Alt+Tab, popup ownership, work-area reservation, toolbar schema, and visual layout too easy to reintroduce.

The recovery goal is a fast, restrained, Mac-inspired Windows desktop whose custom surfaces never compromise native switching, lock-screen safety, app work areas, or diagnosability. Verification must distinguish static configuration guards from interactions that were actually exercised.

## User-facing success criteria

- Native Windows Alt+Tab remains available with no menu open and dismisses any MenuHost popup when switching begins.
- Seelen shortcuts and task-switcher behavior remain disabled.
- Apple, Control Center, Network, and Bluetooth actions open the intended surface without a visible terminal and without spawning duplicate MenuHost processes.
- Bell and date/time open the Windows notification/calendar surface and do not stack over a custom popup.
- The Apple and normally responsive right-side controls remain item-owned; a bounded 19px fallback handles only a Seelen toolbar that Windows reports as click-through.
- Top toolbar and WEG dock survive normal operation and a Seelen restart on every active monitor.
- Maximized client content ends at each monitor's work area and is not covered by the dock.
- Desktop-visible and maximized-window states are both visually coherent.
- Top-bar text, icons, badges, and popup rows are vertically aligned, unclipped, and free of separator/tooltip artifacts.
- The dock remains opaque enough that content does not show through it.
- Warm popup launches feel immediate, repeated use keeps one MenuHost process, and no sustained CPU or memory growth is observed.
- `scripts/verify.ps1` produces evidence for each active monitor rather than ambiguous virtual-desktop edge crops.

## Explicit non-goals

- Replacing Explorer or implementing a complete macOS shell clone.
- Re-enabling Seelen shortcuts, Seelen task switcher, or `@seelen/tb-quick-settings`.
- Reintroducing a MenuHost dock, appbar reservation, background window mover, or Explorer restart loop.
- Changing Windows Security, lock-screen policy, remote-access credentials/configuration, or work-account state.
- Redesigning wallpaper, cursors, launcher providers, or the dock's application set during this recovery pass.
- Treating old QA images as current proof when the interaction was not rerun.

## Current architecture

```mermaid
flowchart LR
    User["Pointer / keyboard"]
    Toolbar["Seelen Fancy Toolbar"]
    Dock["Seelen WEG dock"]
    Protocols["macmakeover-* URI handlers"]
    MenuHost["Resident .NET WinForms MenuHost"]
    Native["Native Windows surfaces"]
    HotCorners["PowerShell hot-corner helper"]
    Launcher["PowerToys / Command Palette"]

    User --> Toolbar
    User --> Dock
    User --> HotCorners
    User --> Launcher
    Toolbar -->|"Apple / sliders / network / Bluetooth"| Protocols
    Protocols -->|"named-pipe command; start fallback"| MenuHost
    Toolbar -->|"bell / date"| Native
    MenuHost -->|"settings, lock, power actions"| Native
    HotCorners -->|"top corner click = Show Desktop; guarded right-side fallback"| Native
    HotCorners -->|"network / Bluetooth / battery / sliders fallback"| MenuHost
    Launcher -->|"Alt+Space"| Native
```

Ownership boundaries:

- Seelen owns rendering and work-area integration for the top bar and bottom dock on both displays.
- MenuHost owns only Apple, Control Center, Network, and Bluetooth popups. It uses `WS_EX_NOACTIVATE`, `ShowWithoutActivation`, and an Alt/foreground dismissal timer.
- Protocol handlers use headless `conhost` launchers to write to the resident MenuHost pipe, with a self-healing `--show` fallback.
- Windows owns Alt+Tab, notification/calendar UI, settings, lock, sleep, restart, and shutdown.
- The hot-corner helper polls for configured corner clicks, popup cleanup, and six non-overlapping right-side fallback zones. Those zones are evaluated only when `WindowFromPoint` does not resolve to Seelen's `Fancy Toolbar`, preventing double firing on the responsive display.

## Environment and baseline evidence

- Active displays: two. DPI-aware bounds are 1920x1200 primary and 1920x1080 secondary, with the secondary positioned above and left of the primary.
- Both displays now expose a stable compact 19px toolbar and a smaller compact-dock reservation; a direct maximized Explorer run stopped above both custom surfaces. The experimental 28px toolbar was rolled back when it did not correct Seelen's primary-display hit region.
- Running core components: Seelen UI 2.7.4, `slu-service`, one `MacMakeover.MenuHost`, Windows PowerShell hot-corner helper, PowerToys, and Command Palette.
- RustDesk, Tailscale, and TeamViewer processes were observed but not inspected or changed.
- Repo and live copies match for the changed Seelen settings, toolbar state, toolbar CSS, dock CSS, and the network plugin.
- `settings_shortcuts.json` differs only by trailing whitespace/newline and is semantically the required disabled JSON.
- Versioned Outlook, Codex, and Claude WEG paths were refreshed to the installed packages. Live state still carries normal unpinned runtime items, so future package-version drift remains a maintenance risk.
- Baseline `scripts/verify.ps1 -CaptureScreenshot` passed and produced `qa/visual-qa-20260710-121233/`.

## Findings, ordered by severity

### High, resolved in this pass: MenuHost popups were hard-wired to the primary monitor

The baseline `MenuForm.OnHandleCreated` used `Screen.PrimaryScreen`. An actual Apple toolbar click on the secondary display opened the menu on the primary display. MenuHost now captures `Screen.FromPoint(Cursor.Position)` before handle creation and uses that screen for placement/DPI context. With the pointer on DISPLAY2, the rebuilt host logged DISPLAY2 and the Apple menu appeared at that display's upper-left edge in `qa/recovery-audit-20260710/postfix-secondary-apple-menu-open.png`. A final actual toolbar-click recheck is still desirable because the post-change proof used the resident pipe command.

### High, resolved in this pass: visual verification was not monitor-correct

The baseline FFmpeg capture was the full 2511x2280 virtual desktop, but `verify.ps1` created `top-130.png` from the virtual desktop's global top and `bottom-240.png` from its global bottom. The verifier now enables DPI-aware screen enumeration, captures the full virtual desktop in both FFmpeg and fallback paths, makes legacy top/bottom files exact copies of the primary-monitor crops, and emits full/top/bottom images for every display. Hash comparison confirmed the legacy files match the primary files.

### High: required interaction acceptance is not yet fully evidenced

The Apple click and Apple-to-Alt+Tab dismissal were exercised successfully. The Windows automation connection then failed to activate normal windows after a shell URI test, so physical corner clicks, Control-Center-to-Alt+Tab, and several real toolbar click paths remain open gates. Protocol and pipe tests do not count as substitutes for those exact clicks.

### Medium: notification/date routing has one implementation for two controls

Both the bell and date/time call `macmakeover-notification-center:`, which runs a headless PowerShell action that sends Win+N. This is compatible with Windows 11's combined notification/calendar surface, but it does not explicitly close MenuHost first. The protocol test did not produce durable screenshot evidence of the surface, so distinct bell/date behavior and no-stacking remain unproven.

### Medium: MenuHost can block its UI thread on external commands

Network and Bluetooth construction call `netsh` or Windows PowerShell synchronously. `RunHidden` calls `ReadToEnd()` before `WaitForExit(timeoutMs)`, so the stated timeout cannot protect against a process that never closes its redirected streams. Warm tests were acceptable (about 371 ms Network and 291 ms Bluetooth), but the failure mode can freeze all MenuHost panels.

### Medium-high: repeated Control Center churn retains resources

Repeated open-close cycles kept one responsive MenuHost PID, but resource use did not plateau. Twenty Apple-only cycles added about 9 MB and 15 handles after an eight-second settle; ten Control-only cycles then added about 3.5 MB and 68 handles after ten seconds. Earlier mixed batches also grew. The resident host was restarted after testing and returned to about 32 MB/231 handles. Control Center state enrichment/timers/process or COM lifetime should be profiled before this risk is accepted.

### Medium: live dock state and restore state drift

Seelen rewrote live WEG state with runtime package paths and a transient Terminal entry. Recent Seelen logs contain a missing Codex icon path error. Absolute versioned WindowsApps paths make restore snapshots fragile across app updates and machines.

### High, mitigated pending user click: primary DPI-scaled toolbar is visually full-width but click-through

Computer-use capture reports the secondary toolbar as a 1920x19 window, but the primary toolbar as a 15x15 target plus a related 1280x19 render. A coordinate click on a primary status icon was rejected because `WindowFromPoint` resolved to Explorer's `FolderView`, not Seelen. Restarting Seelen and restoring the prior 19px visual settings did not change this native hit region, so the image-generated 28px CSS was not the cause. The helper now checks the real window under every top-bar click and routes calibrated Network, Bluetooth, Battery, Control, Notifications, and Date zones only on the click-through instance. The primary route remains user-observed rather than automation-proven because safe UI automation refuses to inject a click through a mismatched target.

### Visual baseline

The two toolbars and docks are present, dock backgrounds are opaque, maximized content stops above the docks, top-bar text is compact and vertically centered, and no bottom hairline was visible. Apple, Control Center, Network, and Bluetooth panels are readable with consistent row alignment. The baseline did not establish a current minimized/show-desktop state.

## Architecture risk assessment

| Area | Evidence | Risk |
|---|---|---|
| Seelen toolbar/WEG ownership | Both monitors render; work areas are reserved; verifier guards performance modes and WEG enablement | Medium: schema and app-path drift remain external dependencies |
| MenuHost popup ownership | Fast warm launches, no activation, one process, Alt dismissal works for Apple | Medium-high: primary-monitor anchoring and synchronous probes |
| URI launch layer | Correct registry commands; no visible terminal in Apple test | Medium: duplicated installers and transient shell ownership |
| Hot-corner helper | Monitor-aware bounds; one process; guarded 19px fallback; verifier rejects overlapping zones | Medium: positional fallback remains a compatibility layer for Seelen's mixed-DPI hit-test defect |
| QA harness | Static guard coverage is strong | High until per-monitor captures and missing interactions are gated explicitly |

## Architecture decision: simplify current architecture

Keep the successful ownership model, but reduce and harden it rather than rebuilding:

1. Keep Seelen as the sole toolbar/dock owner and keep native Windows Alt+Tab/search/notification surfaces.
2. Keep one resident MenuHost for the four custom panels; keep popup placement monitor-aware and keep background probes cancellable with real timeouts.
3. Keep item-owned toolbar actions. Retain the bounded, `WindowFromPoint`-guarded fallback only while Seelen's primary mixed-DPI toolbar remains click-through; replace it with native item clicks when the upstream hit region is fixed.
4. Consolidate protocol registration and notification/menu dismissal behavior in a later task instead of adding another helper.
5. Make per-monitor screenshot output and interaction gates first-class verification artifacts.

A rebuild is not justified: the baseline passes static guards, renders coherently on both monitors, preserves native switching in the exercised Apple path, and keeps one resident host. Keeping the architecture unchanged is also rejected because the observed secondary-monitor failure and unverifiable crop model are structural defects.

## Implementation and post-change result

- Changed `MenuHost` placement to capture the pointer's screen before handle creation; added a verifier regression guard against `Screen.PrimaryScreen`.
- Changed `verify.ps1` to produce DPI-aware virtual and per-monitor screenshot sets while preserving legacy primary crop names.
- Release build passed with zero warnings/errors after stopping the locked resident executable; the rebuilt host was restarted hidden.
- PowerShell parser check, `git diff --check`, `verify.ps1`, and `verify.ps1 -CaptureScreenshot` passed.
- Seelen was restarted through `\Seelen\Seelen UI Service`; both Fancy Toolbar and WEG instances reported Ready on both displays, and post-restart verification passed.
- `fit-windows-to-workarea.ps1 -WhatIf` returned no repair candidates.
- Final inspected screenshot set: `qa/visual-qa-20260710-123039/`, including both displays' full/top/bottom files.
- Both docks remained opaque and below maximized client content; both menu bars remained aligned with no hairline or clipping regression.
- The image-generated 28px toolbar direction was rolled back after it did not repair the native hit target. The final live state uses the stable compact 19px frosted bar, keeps the redesigned compact opaque dock, and retains the inline bounded notification count.
- MenuHost no longer enters the system topmost band; Apple and Control panels both yielded to native Alt+Tab.
- Snipping Tool `New` reached capture mode, and the overlay was dismissed back to a clean desktop.
- Control Center's blocking output read was replaced by cancellable process waiting, timed-out child-tree termination, and per-form cancellation. A warm repeat batch settled at +4 handles with no child process.
- Hot-corner detection now resolves `Screen.FromPoint` and performs a full monitor-bounds check before classifying a corner. The pre-fix log showed repeated `TopLeft click -> ShowDesktop` entries for Bruno clicks; post-fix single and double body clicks left Bruno visible with no new entry.
- Primary-toolbar fallback routing now resolves `WindowFromPoint`, stays inside y=0..18, and uses six calibrated non-overlapping zones. Network, Bluetooth, Battery, and Control item clicks passed on the responsive secondary toolbar; the primary fallback needs the final user click check.
- Final post-rollback inspected screenshot set: `qa/visual-qa-20260710-161422/`. Both displays show the compact bar, the notification total `23` fully inside its target, and healthy docks after a Seelen restart.
- The second acceptance round found and fixed an implementation-label leak: after the bell test, `Windows Shell Experience Host` appeared in both menu bars. Toolbar templates and the verifier now hide that native helper by name/title; `qa/visual-qa-20260710-200033/` confirms both bars are clean after restart.
- That same round did not accept the bell/date interaction: the `Notification Center` CoreWindow became hidden while remaining the foreground window, preventing safe automation from activating Rider or Snipping Tool. Microsoft documents Win+N as the user shortcut but no supported URI for directly opening Notification Center; the current synthetic-key handler remains an open release gate.
- Final inspected screenshot set: `qa/visual-qa-20260710-140026/`, including both displays' full/top/bottom files after the redesign.
- Product acceptance is not complete: physical corner clicks, bell/date surface capture, minimized desktop, the wider maximize app set, and a user-observed lock/PIN check remain open.

## Recovery-pass scope and stop gates

This pass changed only MenuHost behavior/lifecycle, the verifier, Seelen toolbar/dock settings and themes, the hot-corner compatibility router, current WEG pin paths, the generated design reference, and the four recovery documents.

Stop and roll back a runtime change if any of the following occurs: MenuHost activates or enters Alt+Tab; a panel fails to paint; Seelen bars/docks disappear; work-area bounds change; a new MenuHost process remains; parser/build/static verification fails; or post-change screenshots are worse than the baseline.
