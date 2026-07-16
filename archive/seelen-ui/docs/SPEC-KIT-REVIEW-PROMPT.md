# Spec-Kit Review Prompt: mac-makeover Full Audit And Recovery

Paste this into a stronger coding/design model when asking it to review this project. It is intentionally stricter than the previous design prompt: the next model must audit the system, produce a spec-style plan, run adversarial QA, and only make changes that survive evidence-based verification.

```text
You are taking over a Windows 11 desktop-customization project that has repeatedly regressed. Treat this as a recovery/audit assignment, not a normal visual polish task.

Single source of truth:
C:\Users\VineethRao\source\repos\mac-makeover

Do not edit or rely on the old frozen backup:
C:\Users\VineethRao\source\repos\brunel\workspace\desktop\mac-makeover

User assessment:
The project has had mediocre aesthetics and poor performance. That combination is unacceptable. The goal is not more decorative complexity. The goal is a stable, fast, visually coherent Mac-inspired Windows desktop that does not break core Windows behavior.

Primary outcome:
Produce a rigorous audit, a spec-style recovery plan, and a verified improvement path. If the current Seelen/MenuHost approach is too fragile, say so clearly and recommend simplification. Do not keep layering fixes over a bad architecture without proving the architecture can support the required behavior.

Required reading before proposing anything:
- README.md
- CLAUDE.md
- docs\CODEX-HANDOVER.md
- docs\CLAUDE-DESIGN-PROMPT.md
- config\hot-corners.json
- config\seelen\data\seelen-fancy-toolbar\state.yml
- config\seelen\data\seelen-weg\state.yml
- config\seelen\themes\macos-glass\styles\fancy-toolbar.css
- config\seelen\themes\macos-glass\styles\weg.css
- scripts\restore.ps1
- scripts\verify.ps1
- scripts\start-hot-corners.ps1
- scripts\fit-windows-to-workarea.ps1
- tools\MacMakeover.MenuHost\Program.cs

Also inspect:
- git status --short
- git log --oneline -20
- recent qa folders under qa\
- Seelen live logs if running:
  %LOCALAPPDATA%\com.seelen.seelen-ui\logs\Seelen UI.log
  %LOCALAPPDATA%\com.seelen.seelen-ui\logs\SLU Service.log

Do not trust previous claims without verifying them. Prior sessions repeatedly said things were fixed while visual or interaction QA was incomplete.

## Spec-Kit Style Deliverables

Before changing behavior, create or update the following review artifacts in the repo:

1. docs\AUDIT-SPEC.md
   - Problem statement.
   - User-facing success criteria.
   - Explicit non-goals.
   - Current architecture diagram in prose or Mermaid.
   - Architecture risk assessment.
   - Decision: keep current architecture, simplify current architecture, or recommend rebuild.

2. docs\QA-TEST-MATRIX.md
   - Static visual checks.
   - Interaction checks.
   - Performance checks.
   - Regression checks.
   - Exact commands to run.
   - Exact screenshots to capture.
   - Pass/fail criteria.

3. docs\RECOVERY-PLAN.md
   - Ordered tasks.
   - Rollback points.
   - Files expected to change.
   - What each task is proving.
   - How to stop if a task makes the system worse.

4. docs\RISK-REGISTER.md
   - Known fragile areas.
   - Impact.
   - Likelihood.
   - Mitigation.
   - Verification method.

If a formal Spec Kit tool is available, use it. If not, create these markdown files manually with the same intent. Do not skip the artifact phase.

## Non-Negotiable Product Requirements

The final desktop must satisfy all of these:

- Native Windows Alt+Tab works normally.
- Lock-screen PIN entry remains safe.
- Apple icon opens the Apple menu quickly and never opens a terminal.
- Apple menu does not linger over Alt+Tab, Task View, or app switching.
- Control Center opens from the sliders icon and never shows Seelen's old power/options screen.
- Wi-Fi opens the Network panel.
- Bluetooth opens the Bluetooth panel.
- Bell opens notifications, not Control Center.
- Date/time opens calendar/notification surface without panel stacking.
- Dock does not obscure maximized app content.
- Dock does not randomly become transparent.
- Top bar does not overlap app chrome, menu titles, telemetry, notification badges, or window controls.
- Text is vertically centered in all top-bar capsules and menu rows.
- Minimized-window desktop state and maximized-window state both look correct.
- Multiple monitor layout must be considered if more than one display is present.
- No hidden broad pixel zones that accidentally fire while clicking app chrome.
- No background window mover.
- No force-restarting Explorer while Seelen is running.
- No Windows Security disabling/bypass.
- No RustDesk/Tailscale/TeamViewer credential or config work unless explicitly requested.

## Architecture Guardrails

Known current architecture:
- Seelen owns the top toolbar and bottom WEG dock.
- MenuHost is a resident .NET WinForms helper for Apple, Control Center, Network, and Bluetooth panels.
- PowerToys / Command Palette owns Spotlight-like search on Alt+Space.
- Hot corners are handled by scripts\start-hot-corners.ps1.
- Seelen shortcuts are intentionally disabled.

Guardrails:
- Keep Seelen shortcuts disabled:
  {"enabled":false,"shortcuts":{}}
- Do not enable Seelen task switcher.
- Do not reintroduce MenuHost native dock/appbar code.
- Do not reintroduce DockForm, SHAppBarMessage, SetBottomAppBar, or appbar reservation logic in MenuHost.
- Keep MenuHost popups no-activate:
  WS_EX_NOACTIVATE
  ShowWithoutActivation
- Do not call form.Activate() or SetForegroundWindow for MenuHost popups.
- Keep the MenuHost Alt/system-switch and foreground-change dismissal guard.
- Keep Apple and Control Center item-owned through toolbar onClick URI handlers, not broad screen-coordinate helper zones.
- Do not re-add @seelen/tb-quick-settings unless the user explicitly asks for the old Seelen flyout.
- Stop Seelen before editing Seelen config/theme files.

## Known Failure History To Probe

Probe these explicitly. They have all failed before:

- Alt+Tab broken or appearing broken when a custom menu is open.
- Top and bottom bars disappearing after battery/performance mode changes.
- Toolbar blanking due to YAML/schema mistakes.
- Apple click opening a terminal.
- Apple click opening Seelen user drawer instead of Apple menu.
- Sliders/power icon opening ugly Seelen power/options screen.
- Network icon opening a large generic menu instead of Network panel.
- Bluetooth disappearing.
- Battery and charging shown as unrelated items.
- Dock covering maximized app content.
- Dock becoming transparent.
- Top bar text sitting too low in capsules.
- Weird black separator line below top bar.
- Menu items drifting to the middle.
- Top-bar overlap around active app name, telemetry, date, notification badge, and right-side icons.
- Ghost tooltips or hover artifacts.
- Corner show-desktop clicks failing.
- Laggy Apple menu or Control Center cold start.
- Lock-screen PIN input affected by shortcut/task-switcher experiments.
- Visual QA based only on screenshots with maximized windows, while minimized desktop state is broken.

## Required Audit Procedure

Phase 1: Inventory
- Read the required files.
- Record current branch, latest commit, and dirty state.
- Identify all running components:
  Seelen, slu-service, MenuHost, hot-corners PowerShell, PowerToys, RustDesk/TeamViewer if present.
- Identify live Seelen config paths versus repo config paths.
- Identify mismatch between live state and repo state.

Phase 2: Baseline QA Before Changes
- Run:
  .\scripts\verify.ps1 -CaptureScreenshot
- Inspect full screenshot, top crop, and bottom crop under qa\.
- Capture/inspect both:
  - maximized app state
  - minimized/desktop-visible state
- If possible, test on the active display setup rather than assuming one monitor.
- Record specific visible defects with screenshot paths.

Phase 3: Functional Tests Before Changes
Test these before touching code:
- Apple menu open latency and visual result.
- Control Center open latency and visual result.
- Wi-Fi click result.
- Bluetooth click result.
- Bell click result.
- Date/time click result.
- Top-left and top-right physical corner show-desktop behavior.
- Native Alt+Tab with no custom menu open.
- Native Alt+Tab while Apple menu is open.
- Native Alt+Tab while Control Center is open.
- Maximized app bounds relative to dock.
- Minimized desktop state relative to dock and top bar.

Phase 4: Architecture Decision
Before implementing any changes, write a short decision:
- Keep current architecture.
- Simplify current architecture.
- Replace current architecture.

The decision must cite evidence from files, screenshots, and tests. If you recommend keeping the architecture, explain why the known regressions are now controlled by tests. If you recommend simplification or rebuild, specify exactly what to remove and why.

Phase 5: Implementation
- Make the smallest coherent set of changes that improves stability and/or visual quality.
- Prefer removing fragile behavior over adding another helper.
- Prefer boring functional correctness over clever UI tricks.
- Do not make a purely aesthetic change that worsens performance, native behavior, or debuggability.
- Keep commits reviewable.

Phase 6: Adversarial QA After Changes
You must try to break it:
- Open and close Apple menu repeatedly.
- Open Apple menu, then Alt+Tab.
- Open Control Center, then Alt+Tab.
- Open Network, Bluetooth, notifications, and calendar in different orders.
- Click outside each panel.
- Maximize and restore common apps: Chrome, File Explorer, Windows Terminal, Service Bus Explorer if present, Snipping Tool if present.
- Minimize all windows and inspect desktop state.
- Switch power/AC state only if safe and observable; otherwise inspect Seelen performance settings.
- Restart Seelen and verify bars return.
- Run verify again after restart.

## Required Commands

Run these unless there is a clear reason not to:

```powershell
git status --short
git log --oneline -20
.\scripts\verify.ps1
.\scripts\verify.ps1 -CaptureScreenshot
git diff --check
```

If MenuHost changes:

```powershell
dotnet build .\tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release --nologo
```

If PowerShell scripts change, parser-check touched scripts:

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("path\to\script.ps1", [ref]$null, [ref]$errors) | Out-Null
$errors
```

If Seelen config/theme changes:
- Stop Seelen first.
- Apply repo and live config carefully.
- Restart Seelen.
- Capture screenshots after restart.

## Visual QA Requirements

Do not mark complete without inspecting screenshots.

Minimum screenshot set:
- Full desktop.
- Top 130 px crop.
- Bottom 240 px crop.
- Apple menu open.
- Control Center open.
- Network panel open.
- Bluetooth panel open.
- Minimized desktop state.
- Maximized app state with dock visible.

For each screenshot, check:
- Overlap.
- Clipping.
- Vertical alignment.
- Text baseline alignment.
- Icon spacing.
- Badge placement.
- Top bar height and separator line.
- Dock opacity and app-content overlap.
- Hover/active indicators.
- Whether the UI visually communicates click targets correctly.

## Performance QA Requirements

Measure or estimate with evidence:
- Apple menu opens fast enough to feel immediate.
- Control Center opens fast enough to feel immediate.
- Repeated open/close does not create duplicate MenuHost processes.
- Seelen restart returns bars reliably.
- CPU/memory telemetry does not cause visible flicker or layout shifting.

If you cannot measure precisely, say what was observed and what remains unmeasured.

## Acceptance Criteria

The task passes only if:
- All non-negotiable product requirements pass.
- verify.ps1 passes.
- Required screenshot set is captured and inspected.
- Alt+Tab works in normal state and while custom menus are open.
- Dock does not cover maximized app content.
- No visible terminal appears from Apple/Control Center actions.
- No Seelen old power/options flyout appears from sliders/control actions.
- The result is either clearly more stable, or the recommended next step is a documented rollback/simplification plan.

## Expected Final Response

Return:
- Architecture decision.
- Audit findings, ordered by severity.
- Files changed.
- Commands run and results.
- Screenshot paths inspected.
- Interaction tests run and results.
- Remaining risks.
- Whether you committed.
- Commit hash if committed.

Do not say "done", "fixed", or "all good" unless the required QA was actually performed.
```
