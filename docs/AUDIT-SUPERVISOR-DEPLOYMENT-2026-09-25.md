# Supervisor and deployment source audit — 2026-09-25

## Scope and starting state

This audit was performed in the managed worktree
`C:\Users\VineethRao\.codex\worktrees\b101\mac-makeover` from base commit
`4a2b45baf8564799fe45ec7eb9373c91e872d356` (detached `HEAD`). The audit owns
`tools/MacMakeover.Supervisor/**`, every PowerShell script under `scripts/**`,
the six archived Seelen rollback/verification scripts under
`archive/seelen-ui/scripts/**`, and this report. No commit, push, pull request,
UAC request, deployment, registry/settings mutation, VPN action, scheduled-task
change, or live shell-process termination was performed.

The source inventory covered:

- `tools/MacMakeover.Supervisor/MacMakeover.Supervisor.csproj` and
  `tools/MacMakeover.Supervisor/Program.cs`.
- All 36 root scripts: build/capture/completion, PowerToys and reliability
  helpers, app/protocol installers, hot-corner helpers, dock and native-shell
  installers, promotion/preparation/request/invocation/switch/repair scripts,
  performance measurement, task registration, profile/preflight/regression/
  pin/system verification, and the top-level `verify.ps1`.
- All six archived scripts: `backup-current.ps1`, `pin-apps.ps1`,
  `Restore-SeelenProfile.ps1`, `Restore-SeelenSystemProfile.ps1`, `restore.ps1`,
  and `verify.ps1`.
- `README.md` and `docs/NATIVE-SHELL-KNOWN-QUIRKS.md` were read for operating
  constraints before source changes.

## Findings fixed

### Supervisor hot path and lifecycle ownership

The former watchdog enumerated each component with `GetProcessesByName` on every
500 ms loop and re-probed Explorer on a five-second cadence. That was consistent
with the previously observed 9.83% one-core supervisor CPU sample.

`Program.cs` now uses `ProcessLifetimeObserver` per component and Explorer:

- The observer enumerates only at startup, while a component is missing, during
  bounded task-start verification, and during bounded Explorer reconciliation.
  A healthy component is represented by retained `Process.Exited` registrations.
- Every observation is restricted to the supervisor's current Windows session.
  All matching PIDs are tracked, so multiple same-name instances do not make the
  observer lose a healthy instance.
- PID reuse is guarded by the retained `Process` wrapper and tracked-object
  identity; an old exit callback cannot remove a newer wrapper for the same PID.
- Registration, exit, prune, replacement, and observer disposal all use one
  release path with event unsubscription, an atomic released flag, and explicit
  `finally` cleanup on supervisor loop exit.
- A missing process is reconciled at a bounded one-second cadence. Existing
  launcher/child-state classification and exponential launch backoff remain in
  place. Explorer remains on its five-second readiness probe.
- `schtasks.exe` uses `ProcessStartInfo.ArgumentList`; stderr is drained while
  the launcher runs; the launcher has a bounded five-second wait and a bounded
  kill/wait fallback.

The self-test now includes a harmless `--lifecycle-helper` child mode. It starts
two same-name children, observes both, waits for their exit, and verifies the
observer returns to its baseline count. It also injects a registration failure
after a same-PID replacement has entered the ledger, proving that both the old
and replacement wrappers are released and no stale active count remains.

### Promotion freshness and stale-marker prevention

Promotion state previously allowed a historical `EXIT=0` marker to be mistaken
for the current UAC attempt. The flow now correlates one fresh run end to end:

1. Preparation removes an old prepared marker and writes a new 32-hex
   `promotionRunId` and UTC `preparedAt`.
2. The unelevated request validates the run ID, writes `STATE=REQUESTED` before
   starting UAC, and passes the ID to the elevated script. A cancelled or
   failed UAC launch therefore cannot leave an old success marker looking fresh.
3. The elevated phase writes `STATE=RUNNING`, passes the ID to the privileged
   switch, and writes `STATE=SUCCEEDED`/`EXIT=0` or `STATE=FAILED`/`EXIT=1` for
   that exact run.
4. The privileged system-state JSON records the same ID. Completion requires the
   prepared ID, result ID/state/exit, and system-state ID all to match.

The UAC boundary remains intact; no elevation bypass was added.

### Script safety and rollback hardening

The source audit fixed the following classes of defects:

- Native task stop/start, promotion, profile verification, hot-corner helpers,
  PowerToys/Awake handling, and archived rollback verification now constrain
  process discovery or termination to the current interactive session.
- Dock `--shutdown` callers that own the promotion path now inspect the child
  exit code. `winget`, registry export/import, build/reliability commands, and
  verification wrappers retain explicit external-command failure checks.
- The native installer is native-only by default. Installing retired YASB and
  Windhawk integrations requires the explicit `-InstallLegacyIntegrations`
  switch; the obsolete Windhawk dock recommendation was removed. The installer
  delegates to the run-ID-aware `Promote-NativeShell.ps1` flow rather than
  calling the privileged switch directly.
- Optional saved-state properties in both archived rollback phases are read
  defensively under `Set-StrictMode`, and registry export/import failures are
  surfaced rather than silently producing incomplete backups/restores.
- The archived backup script no longer contains a user-specific source path by
  default; it defaults to the current repository and still accepts an explicit
  source override.
- MDM wallpaper path checks require the Windows wallpaper directory itself or a
  path below it, avoiding a sibling-prefix escape such as `wallpaper-evil`.
- Existing Windhawk binary content is SHA256-checked against the pinned config
  before reuse; a mismatch or unreadable hash triggers a verified download.
  The hot-corner keepalive task no longer has a two-minute execution limit for
  a long-lived helper.
- Regression/process helper cleanup is bounded, process wrappers are disposed
  where retained, stale `$LASTEXITCODE` assumptions were removed from the build
  result path, schedule arguments are quoted, and passing helper scripts now
  return explicit zero exit codes.
- `Test-NativeShellPreflight.ps1` parses every root and archived PowerShell file
  instead of a hand-maintained subset, and its static checks cover the observer,
  native-only installer contract, and promotion run correlation.
- `Measure-ShellPerformance.ps1` reports custom, shell-only, and aggregate
  diagnostics. Shell-only names are derived by subtracting custom names, so
  including `explorer` in `CustomProcessNames` cannot double-count its CPU or
  memory in aggregate shell metrics.

## Verification performed

All commands below were run from the audit worktree and completed successfully:

- `git diff --check`.
- `dotnet build tools/MacMakeover.Supervisor/MacMakeover.Supervisor.csproj --configuration Release --no-restore` — 0 warnings, 0 errors.
- `dotnet run --project tools/MacMakeover.Supervisor/MacMakeover.Supervisor.csproj --configuration Release --no-build -- --self-test` — passed. The same self-test passed three consecutive iterations after the final observer race fixes.
- PowerShell AST parsing of all 42 scripts in `scripts/*.ps1` plus `archive/seelen-ui/scripts/*.ps1` — 42 files passed.
- `scripts/Test-NativeShellPreflight.ps1 -DeploymentRoot %LOCALAPPDATA%\MacMakeover\bin -SkipDownloadCheck` — passed static/staged preflight, including the existing staged artifacts and headless component checks; it reported one display and 16 native pinned shortcuts.
- A bounded 15-second read-only measurement with `MacMakeover.Supervisor` plus an intentional missing process. The summary recorded the Supervisor, reported the intentional missing name, kept all observed processes responsive, and produced the new shell-only metrics.
- A second bounded 15-second read-only measurement with `explorer` included in the custom set. The summary moved `explorer` out of `shellOnlyProcessNames` (leaving only `dwm`), demonstrating the no-double-counting rule.

The measurement artifacts were written outside the repository under the current
user temp directory (`%TEMP%\mac-makeover-supervisor-audit`). They are not part
of the source change.

## Unresolved risks and limits

- The live promotion and rollback workflows were intentionally not executed.
  They require UAC, registry/policy writes, scheduled-task changes, Explorer
  restarts, and process termination. Their source contracts are covered by
  parser/static checks, but an actual privileged acceptance run remains a
  separate operator-controlled test.
- The self-test exercises current-session behavior and multiple same-name
  processes. A second Windows interactive session was not created solely for
  testing; cross-session behavior is source-guarded by `SessionId` filtering.
- The existing live regression mode can force-stop and restart production shell
  components; it was not run under this audit because doing so would violate the
  no-live-termination constraint. The staged preflight is a static/staged gate,
  not a substitute for a privileged production acceptance run.
- Process exit notifications are asynchronous and can be denied or delayed by
  Windows. The observer therefore keeps bounded reconciliation for missing
  processes; it does not claim instantaneous recovery or prove behavior under
  every Windows security/desktop-session configuration.
- Preparation still performs many user-profile changes before its final prepared
  marker is written. The orchestrating promotion catch path restores the
  interactive shell on failure, but a real interrupted mid-preparation rollback
  remains an operational scenario to exercise separately.
- The performance samples validate instrumentation and missing-process handling;
  they are not a before/after CPU acceptance benchmark for an installed shell.
