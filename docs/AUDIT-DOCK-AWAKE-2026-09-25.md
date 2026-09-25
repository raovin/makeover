# Dock and Awake source audit — 2026-09-25

## Status and boundary

This is a source audit with bounded fixes in the delegated ownership area. The
worktree started clean at 4a2b45baf8564799fe45ec7eb9373c91e872d356
(origin/codex/native-tray-audit) in the requested isolated worktree. No commit,
push, pull request, deployment, registry/settings mutation, VPN action, production
process termination, or external send was performed.

The repository guidance reviewed before implementation was README.md and
docs/NATIVE-SHELL-KNOWN-QUIRKS.md. Their Explorer-window, truthful AppBar,
UI-thread display teardown, tray-snapshot, schedule, and testing contracts remain
the acceptance boundary.

## Coverage inventory

Reviewed every owned source, build, manifest, settings, test, and documentation
input:

- tools/MacMakeover.Dock/Program.cs — CLI modes, regression harness, AppBar
  geometry/recovery, display rebuild, Dock rendering/input, asynchronous state
  capture, process/window identity, icons, pin persistence, Explorer policy, and
  failure paths.
- tools/MacMakeover.Dock/NativeMethods.cs,
  tools/MacMakeover.Dock/MacMakeover.Dock.csproj, and
  tools/MacMakeover.Dock/app.manifest — Win32 interop, target/build settings,
  DPI awareness, and linked native pin data.
- tools/AwakeAndAvailable/Program.cs, AppSettings.cs, ScheduleEngine.cs,
  ScheduleSelfTest.cs, TrayApplicationContext.cs, TrayIconState.cs,
  NativeMethods.cs, and MenuDismissalMonitor.cs — CLI diagnostics,
  persistence, DST/boundary state, power requests, input modes, timers, menus,
  hooks, tray resources, and shutdown.
- tools/AwakeAndAvailable/AwakeAndAvailable.csproj,
  app.manifest, build.ps1, README.md, and AUDIT.md — build/publish,
  execution-level, resource embedding, deployment assumptions, user contracts,
  and prior findings.
- tools/AwakeAndAvailable/Scripts/create-icon.py plus all files under
  tools/AwakeAndAvailable/Assets/ — icon-generation inputs and generated
  multi-resolution resources. No asset changes were needed.

## Confirmed findings and changes

### Dock display/exit callbacks could race UI-owned form state

SystemEvents.DisplaySettingsChanged and the registered exit wait callback can
run away from the WinForms thread, while display rebuild and FormClosed handlers
mutate the form list. The previous exit callback also used a one-shot wait: if it
observed the deliberate zero-form teardown window, shutdown could be consumed
without a dispatcher.

The Dock now uses a volatile dispatcher reference instead of enumerating the
mutable form list off-thread. Exit requests are retained in DockExitRequestState
and dispatched after replacement forms exist; rebuild completion on the UI thread
also consumes a pending request when the replacement set is empty. The regression
suite covers both the no-dispatcher transition and the zero-form replacement case.

### Multi-monitor refresh repeated expensive discovery

Every Dock form owns a one-second timer and previously performed its own complete
process identity scan plus window enumeration. This multiplied Process/module
access and EnumWindows work with each display.

DockStateCapture now shares one read-only snapshot for same-signature captures
within a 400 ms window, uses monotonic Stopwatch timestamps, and invalidates on
pin-definition changes. The shared capture also reuses known pinned process
identities while grouping window snapshots. Each form retains its own generation
check and UI apply path, so stale work cannot overwrite a pin reload.

### Dock regression probes were not isolated across immediate repeated runs

A bounded five-run stress pass reproduced File.Copy failing because the fixed
MacMakeover.QaProbe.exe image was still locked by a previous probe process.
The regression harness now uses a per-run GUID-named probe image. Five consecutive
headless Dock runs pass after this change.

### Pin-state persistence had a cross-instance temporary-file collision

Preview and production Dock instances intentionally use different mutex names but
share pin state. A fixed .tmp sibling could therefore collide during concurrent
pin writes; load/save access failures could also escape the persistence boundary.
The temporary name is now process-specific, directory-less test paths fall back
to ., and expected I/O/access failures leave the running Dock usable while
retaining the old state on disk.

### Dock launch failures could escape a click handler

A stale or unavailable non-Explorer target could make Process.Start throw from
the UI click path. Launch attempts now catch the expected Win32, file, argument,
and invalid-operation failures and record them through Debug; successful target
resolution and the explicit %WINDIR%\explorer.exe Explorer policy are unchanged.

### Awake transient UI resources and hook failure behavior

Safe-point capture and pointer restoration used local timers that were not tracked
by shutdown. A low-level hook callback could also propagate a teardown exception
through user32. The tray now tracks transient timers, disposes them on exit, and
restores a pending pointer only when it is still at the injected point. Hook
callbacks are exception-contained and always continue through user32.

The input diagnostic and Test Teams pulse path now distinguish a failed
GetLastInputInfo call from a real zero-idle reading, preventing a false
successful verification.

## Preserved contracts and judgment calls

- Existing Portugal schedule semantics, DST handling, 15-second reconciliation,
  manual override expiry, safe-point confirmation, and persisted-mode
  normalization were already covered and were not rewritten.
- Existing AppBar recovery limits, registration ordering, bottom-edge geometry,
  per-monitor DPI calculations, Explorer class filtering, GDI/COM icon-copy
  lifetimes, pin generations, and bounded background refresh behavior were
  preserved.
- The capture cache is intentionally short-lived rather than a permanent global
  snapshot: it removes near-simultaneous per-monitor duplication while bounding
  visible state age to roughly 400 ms. Monotonic timing prevents wall-clock
  changes from extending it.
- No production pin file, Awake settings file, AppBar registration, power request,
  tray menu, or live shell component was touched by verification.

## Verification evidence

All commands ran from the isolated worktree:

- dotnet build tools/MacMakeover.Dock/MacMakeover.Dock.csproj --configuration
  Release — passed with 0 warnings and 0 errors.
- dotnet build tools/AwakeAndAvailable/AwakeAndAvailable.csproj --configuration
  Release — passed with 0 warnings and 0 errors.
- MacMakeover.Dock.exe --regression-test — passed, including the new cache and
  exit-state checks.
- The Dock regression was repeated five times serially; all five exited 0.
- AwakeAndAvailable.exe --verify-schedule with a temporary output path — passed
  all 17 schedule tests; repeated three times serially, all exited 0.
- git diff --check — passed. Git emitted only normal LF/CRLF normalization
  warnings while inspecting the working diff.

## Unresolved risks and evidence limits

- Physical multi-monitor hot-plugging, mixed-DPI movement, Explorer restart,
  AppBar reservation repair against a live taskbar, and pointer-level context
  menu stress were not run. The known-quirks document correctly treats those as
  manual/physical acceptance gates.
- No live production Dock/Awake instance was stopped or reconfigured, so this
  audit does not claim runtime proof of task restart behavior, power-request
  lifetime under sleep/resume, or real tray-click dismissal across integrity
  boundaries.
- The headless regression exercises current-session window classification and
  probe lifetimes, not every third-party window class, packaged-app identity, or
  hardware topology.
- The Awake schedule remains intentionally reconciliation-based with up to
  approximately 15 seconds of boundary latency, as recorded in its existing
  audit. Exact-to-the-second activation was not made a speculative change.
- There is no conventional unit-test project; pure policy coverage remains inside
  the executable regression/self-test modes.

## Git / handoff

Changes are intentionally uncommitted and unpushed for parent inspection. There
is no pull request. The final modified-file set is limited to the delegated
Dock/Awake sources plus this audit record.
