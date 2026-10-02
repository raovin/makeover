# Vesper Shell source audit — 2026-10-02

## Status and starting state

**Status: complete for source fixes and safe verification.** The audit started on
`codex/native-tray-audit` at `aad8c6de0be98cc707f755de1c6cb046ef49f4a8` with a clean
working tree. Changes remain uncommitted. The delegated Luna task is
`01a0fd4e-6eb0-7fc2-95d7-83d078b2879c` on host `local`; its primary chat is
`01a0fd4c-7dd2-73d1-8a0e-61494f2f146f`.

Before editing, I read `README.md`, `CLAUDE.md`,
`docs/NATIVE-SHELL-ARCHITECTURE.md`, the July reliability audit, all three detailed
September 25 source-audit records, the September 25 hardening review, and
`docs/DOCK-ICON-CRASH-2026-09-28.md`. Historical findings were treated as review
leads; the current source and self-test paths were checked directly.

Coverage included the five native projects and their current test modes:

- `MacMakeover.MenuBar`: per-monitor AppBar teardown, tray icon/cache ownership,
  telemetry snapshots, current-session MenuHost client, and power-state self-test.
- `MacMakeover.MenuHost`: current-user named-pipe server/client boundaries, command
  validation and queueing, menu/resource disposal, confirmation-gated power actions,
  and Core Audio self-test behavior.
- `MacMakeover.Dock`: display/exit dispatch, capture cache, window/process ownership,
  pin persistence, icon handle conversion, and the September 28 crash fix. The
  current `DockIconHandle.Copy` duplicates borrowed HICONs, disposes decoded icon
  and bitmap objects, and destroys owned handles; running-window lookup uses
  bounded `SendMessageTimeoutW` calls and tries later candidates after bad handles.
- `MacMakeover.Supervisor`: current-session process lifetime observation, bounded
  task restart/backoff, startup logging, and self-test child cleanup.
- `AwakeAndAvailable`: schedule boundary/DST resolution, settings normalization,
  transient timer and input-hook disposal, and safe `--verify-schedule` mode.
- Root PowerShell scripts were inventoried and parsed, including promotion,
  deployment, rollback verification, regression, profile/preflight, task, and
  recovery entry points. Native pins, hot-corner, PowerToys, PowerToys Run, and
  Command Palette configuration were inspected; six JSON configuration files were
  independently parsed by the parent.

## Confirmed findings and changes

### Regression suite could test stale Release outputs

`Test-NativeShellRegression.ps1` built a staged package but resolved four checks
from `tools/*/bin/Release` first, preferring the non-RID path. `Build-NativeShell.ps1`
publishes `win-x64`, so an older non-RID binary could silently receive a passing
result. The regression runner now tests all five executables from one exact root:
its fresh temporary stage after a build, or the supplied `DeploymentRoot` with
`-SkipBuild`. It no longer falls back to repository Release directories, and its
evidence records each executable path. Preflight statically guards this contract.

### MenuHost pipe name crossed interactive-session boundaries

MenuHost's mutex was already `Local\` scoped, but the named pipe was machine-wide.
Two logons for the same user could therefore send a panel request to the other
session's MenuHost. MenuHost and MenuBar now construct a pipe name containing their
Windows session ID. The four protocol installer scripts launch `MenuHost --show`
directly so the existing Apple, Control Center, Network, and Bluetooth commands
reach the host in the caller's session. The retired hot-corner helper uses the same
session-qualified name. Existing URI protocol names and command tokens are
preserved. Pure self-tests verify different session IDs produce different pipe
names.

### Supervisor logging could prevent watchdog startup

Supervisor previously called `Directory.CreateDirectory` before entering its
monitoring loop, outside the fail-safe logger. An unavailable or denied log
directory could terminate the watchdog. Directory creation and writes now catch
expected path, I/O, access, and security failures and continue without logging.
The self-test uses a temporary file as a deliberately invalid parent directory to
exercise this path.

### Profile capture assumed optional registry values existed

Under strict mode, the initial profile snapshot dereferenced `Settings` and
`Wallpaper` from possibly absent registry results. Snapshot capture now checks
key/value existence. The `Settings` value is assigned directly before the
snapshot hashtable is built, preserving the registry's `byte[]` type, and only a
binary value with the expected length is interpreted. `-SelfTestOnly` injects a
fake registry-key reader and exercises the full capture path for missing
key/value, enabled/disabled binary values, malformed data, and byte-array
preservation without reading or changing the user's registry.

### Core Audio self-test could leave volume changed after an error

The Core Audio self-test restored volume only on its straight-line success path.
It now attempts restoration in `finally`, reports probe and restoration failures,
and has an injected failure regression that verifies the original level is written
again. Preflight and profile checks gained `-SkipLiveAudioCheck` for static and
read-only runs. The README explains that the actual audio check briefly adjusts
master volume.

## Verification

Commands and results from this audit:

- `scripts/Build-NativeShell.ps1 -Destination qa/audit-20261002/staged` — passed;
  all five projects published in Release, and the stage contains their executables
  plus `deployment-manifest.json`.
- `scripts/Test-NativeShellRegression.ps1 -SkipBuild -DeploymentRoot qa/audit-20261002/staged -OutputDirectory qa/audit-20261002/regression` — all six safe checks passed:
  Dock regression, MenuBar self-test, MenuHost IPC/decision regression, Supervisor
  self-test, all 17 Awake schedule cases, and the 15-second missing-process
  performance smoke test. The evidence file records the staged paths for each
  executable: `qa/audit-20261002/regression/20261002-173849-native-shell-regression.json`.
- `scripts/Test-NativeShellPreflight.ps1 -DeploymentRoot qa/audit-20261002/staged -SkipDownloadCheck -SkipLiveAudioCheck` — exit 0; parser and source invariants
  passed, reporting one connected display and 16 native taskbar shortcuts.
- `scripts/Test-NativeShellProfile.ps1 -SkipLiveAudioCheck` — exit 0 against the
  existing installed deployment; read-only process, hash, tray, Dock, work-area,
  and profile checks passed. This validates installed binaries, not the new staged
  binaries.
- `scripts/Prepare-NativeShellUserProfile.ps1 -SelfTestOnly` — exit 0; missing,
  binary true/false, and malformed registry snapshot fixtures passed.
- PowerShell AST parsing of all 42 root and archived scripts — passed.
- `git diff --check` — exit 0.

The parent independently repeated the five Release publishes and staged checks,
reported all six regression checks passing, parsed all 42 scripts and six JSON
config files, passed all 21 native pin checks, passed the installed profile check,
and confirmed a missing regression stage fails without a Release-path fallback.

## Limits and handoff

No binaries were copied to the production deployment. No user registry, settings,
scheduled tasks, network, power state, or running shell process was changed. The
live audio self-test, interactive Alt+Tab, live recovery, UI panels, Explorer
restart, and promotion were not run. The profile verification used
`-SkipLiveAudioCheck`; the audio fixture used injected delegates only.

The host exposed one 1280×800 display. There was no physical mixed-DPI or
multi-monitor check, no second interactive logon for end-to-end pipe routing, and
no visual desktop signoff. The session-name tests establish distinct names, while
real multi-session Windows delivery remains an environment acceptance check.
Existing installed URI handler registry values were not rewritten; the updated
installer scripts will register the session-aware `--show` command when the normal
deployment workflow next installs them.

Git remains on `codex/native-tray-audit` at the original base, with source changes
uncommitted for review. No commit, push, or pull request was created; a PR was not
authorized.
