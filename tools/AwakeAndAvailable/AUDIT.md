# Project audit

Audit date: 2026-07-30

## Scope

Reviewed all C# source, the project and application manifests, build script, settings lifecycle,
schedule behavior, Windows input and power interop, tray-menu UX, deployment assumptions, and tests.

Grok CLI was invoked repeatedly for the requested independent audit. Its authenticated plan runner
returned only planning messages, while its code-review and bundled-source runs timed out without a
final report. An earlier Grok schedule review informed the pure state model and boundary tests.
No Grok findings are represented here as completed when the CLI did not return them.

AGY CLI was not installed or available on `PATH`. The machine contains the Antigravity desktop
application, but no `agy`, `agy-cli`, or `antigravity` command-line executable.

Follow-up: AGY CLI 1.1.8 was later located in Ubuntu WSL and authenticated. A read-only audit with
`gemini-3.6-flash-high` returned a deployable verdict and identified an explicit safe-click guard,
final context-menu disposal, and visible-menu refresh safety as worthwhile fixes. A second focused
implementation review with `gemini-3.1-pro-high` confirmed the patch strategy. Those fixes are now
included below.

## Findings

### P1 — Invalid persisted mode could enter click handling and crash

`ScheduleEngine.NormalizePersistentMode` previously passed unknown enum values through. In
`TrayApplicationContext.PerformTeamsActivity`, any value other than the two pulse modes fell into
the safe-click branch and dereferenced unset click coordinates.

**Resolution:** normalization now explicitly accepts known values and maps unknown or safe-click
values to `KeyboardAndMousePulse`. Regression coverage was added.

### P2 — Settings writes were vulnerable to partial-file corruption

`AppSettings.Save` wrote directly to the live JSON file. Process termination or an interrupted write
could leave malformed settings.

**Resolution:** settings serialize to a sibling temporary file and replace the live file only after
the write succeeds. Failed writes no longer terminate the tray process.

### P2 — Cursor restoration could override returning user input

The safe-click restore timer always moved the pointer back after 75 ms. A user returning during that
small window could have their movement overwritten.

**Resolution:** the pointer is restored only if it is still exactly at the saved click point.

### P3 — Schedule menu showed an unusable row most of the time

`Resume schedule now` was permanently visible but disabled unless an override existed.

**Resolution:** the schedule remains a single top-level checkbox, and the resume action appears only
during an override. The label now makes the timezone and hours explicit.

### P3 — Schedule boundary reconciliation has up to 15 seconds of latency

`TrayApplicationContext` evaluates the schedule with a 15-second timer. This is deliberately robust
across clock changes and sleep/resume, but activation or deactivation can occur up to 15 seconds
after the displayed boundary.

**Recommendation:** acceptable for presence automation. If exact-to-the-second behavior becomes a
requirement, use a one-shot boundary timer plus a slower reconciliation timer.

### Resolved — Unexpected activity mode could still fall through to click handling

Even with persisted values normalized, `PerformTeamsActivity` implicitly treated every remaining
mode as safe-point clicking.

**Resolution:** safe-point clicking now has an explicit mode branch and nullable-coordinate guard.
Unknown modes are disarmed, persisted as a bounded manual override when scheduling is active, and
reported without dereferencing click coordinates.

### Resolved — Background status refresh could close an open tray menu

Pulse updates rebuilt and disposed the context menu every interval, including while it was visible.

**Resolution:** visible menus defer rebuilding until their `Closed` event. Shutdown detaches that
handler to prevent a deferred rebuild while resources are being disposed.

### Resolved — Final context menu was not explicitly disposed

**Resolution:** `ExitThreadCore` detaches and disposes the final `ContextMenuStrip` before disposing
the notification icon.

### P3 — Deployment is machine-specific

`build.ps1` produces a framework-dependent `net10.0-windows` executable. This computer has the
required runtime, but copying the executable to another machine may fail.

**Recommendation:** keep the current small build for this computer; use a self-contained publish
only if distribution becomes a requirement.

## Strengths

- Schedule logic is isolated and deterministic.
- Europe/Lisbon is used independently of the machine timezone, with a Windows fallback.
- Work hours use correct half-open semantics: 09:00 inclusive, 18:00 exclusive.
- Manual overrides expire at the next schedule boundary.
- Coordinate clicking never silently resumes after restart.
- `SetThreadExecutionState` is applied and cleared on the same UI thread.
- Native input acceptance and Windows idle reset have dedicated diagnostics.
- The single-instance event reopens the existing tray menu instead of spawning duplicate workers.

## Remaining recommendations

1. Add a conventional test project if this grows beyond a personal utility.
2. Add structured file logging only if diagnosing future presence-client changes becomes necessary.
3. Keep safe-point clicking an explicit fallback; prefer the keyboard/mouse pulse.
