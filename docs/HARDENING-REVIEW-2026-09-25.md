# Native shell hardening review — 2026-09-25

## Scope and review process

This follow-up implements the confirmed findings from the September 25 performance
review and extends the audit across all five native components, their build inputs,
36 root PowerShell scripts, and six archived rollback/verification scripts. The
three detailed coverage records are:

- [Supervisor and deployment](AUDIT-SUPERVISOR-DEPLOYMENT-2026-09-25.md)
- [MenuBar and MenuHost](AUDIT-MENUS-2026-09-25.md)
- [Dock and Awake](AUDIT-DOCK-AWAKE-2026-09-25.md)

Three isolated Codex tasks used the explicitly requested GPT-5.6 Luna / Max lane.
The parent inspected the actual diffs, requested corrections, integrated the
accepted changes, and independently reran checks. Grok CLI reviewed IPC and command
dispatch; AGY CLI reviewed Dock cache/exit handling and Supervisor process ownership.
Those external reviews were instructed to be read-only; this is not a claim of
OS-enforced read-only isolation. Their findings were checked against the source,
including rejecting false positives and fixing confirmed ownership/scheduling bugs.

The parent also checked tracked JSON configuration, pin identities, build/runtime
inputs, and operating documentation. This is a source review of the project, not
an audit of Windows, third-party application internals, or every historical asset.

## Accepted changes

- Supervisor retains process lifetime observations instead of repeatedly scanning
  healthy processes. Exit cleanup, PID replacement, failure backoff, and session
  filtering remain explicit and tested.
- Tray discovery filters candidate names before expensive module queries and
  caches executable metadata. Missing tooltips retain fallback names; a bad
  registry row cannot discard the entire result. Crowded bars expose remaining
  applications through a `+N` overflow menu.
- MenuHost bounds command length, idle-client time, and pending commands. Its
  current-user pipe accepts only the supported commands and processes queued work
  on separate UI timer turns. A real isolated message loop verifies heartbeat
  progress during a command flood.
- Dock shares short-lived state capture across displays, retains shutdown requests
  during display reconstruction, and tolerates pin-save/launch failures. Awake
  disposes transient timers and contains hook callback failures.
- Promotion markers now identify the exact attempt, preventing stale success from
  being accepted after UAC cancellation. Script process operations use session
  filters, rollback reads optional state defensively, and external failures are
  surfaced. Native installation no longer installs legacy shell integrations by
  default.

No active feature was removed speculatively for performance. The changes remove
redundant work and improve failure behavior. Archived files are inactive and deleting
them would not establish a runtime saving. Provider polling remains a separately
measurable optimization opportunity.

## Parent validation

All five integrated Release builds and their relevant self-test/regression modes
passed. MenuHost's IPC regression uses a unique pipe and injected command handler;
it does not change networking or open production menus. Awake's 17 schedule cases
passed without exercising live input/pulse actions.

Four synthetic MenuBar renders were visually inspected: 1280px normal, 800px
narrow, and 1280px at scale 2 with 11 and 32 tray entries. The crowded fixture
shows nine direct icons and a `+23` overflow control. These are offscreen fixtures,
not screenshots of the user's desktop.

The combined staged preflight passed, including PowerShell parser checks and
the updated overflow/notification contracts. The full noninteractive regression
script passed all six checks, including its missing-process performance-sampler
test. The staged tray snapshot contained all 11 current applications, including
Tailscale. Evidence is retained in ignored `qa/hardening-regression`,
`qa/hardening-staged-tray.json`, and `qa/offscreen-hardening`.

## Deployment and live recovery

Source commit `b80f221` was pushed to `codex/native-tray-audit`. The parent backed
up the deployed directory to
`%LOCALAPPDATA%\MacMakeover\backups\hardening-20260925-123343`, temporarily
disabled the five component tasks, stopped the components, copied the verified
staged artifacts, and checked every executable against the deployment manifest.
The tasks were re-enabled, Explorer restarted, and all five components restarted
through the existing interactive scheduled tasks.

This was a binary upgrade using the existing privileged configuration. No new
UAC-protected promotion was completed, and old promotion markers were not treated
as current evidence. The updated privileged scripts are source-reviewed and
statically checked, but their full elevated execution remains unverified.

`Test-NativeShellProfile.ps1` passed against the running deployment, including
executable hashes, process presence, and work-area checks. All 21 archived pins
passed `Test-NativeTaskbarPins.ps1`.

The live recovery regression passed all 12 requested checks:

| Recovery check | Observed time |
| --- | ---: |
| Supervisor restores MenuHost | 0.84 s |
| Supervisor restores MenuBar | 0.54 s |
| Supervisor restores Dock | 0.56 s |
| Scheduled watchdog restores Supervisor | 34.70 s |
| Restored Supervisor resumes MenuHost recovery | 0.53 s |

The profile/work-area gate passed after the MenuBar and Dock restarts, and cleanup
confirmed one instance of every recovery target. Awake was left running; its
schedule test does not exercise live input injection. The evidence file is
`qa/hardening-live-recovery/20260925-123454-native-shell-regression.json`.

The deployed tray snapshot also contained all 11 current applications, including
Tailscale and Awake (`qa/hardening-deployed-tray.json`).

## Post-deployment resource sample

The baseline used 180 samples before this hardening deployment. The follow-up
used 300 samples (about 325 seconds elapsed); each summary excludes its first
five samples. All five expected components were present and responsive throughout
both samples, and each retained its PID throughout the follow-up.

| Metric, five custom components | Baseline | Follow-up |
| --- | ---: | ---: |
| Median CPU, normalized across 16 logical processors | 0.998% | 0.264% |
| p95 CPU | 1.491% | 0.459% |
| Median private memory | 145.828 MB | 125.266 MB |
| Median working set | 101.309 MB | 323.992 MB |
| Median handles | 1,789 | 1,840 |

Observed median CPU was approximately 74% lower. This is not an isolated causal
benchmark: system CPU median was also lower (16.047% versus 7.743%), the shell had
restarted, memory pressure differed, and concurrent audit processes had finished.
Private memory was lower, but resident working set was higher; this does not
support a blanket claim that every memory measure improved. The handle increase
is small and the interval is too short to diagnose a leak.

Independent per-process CPU deltas over the follow-up interval, as percent of one
logical core, were Supervisor 0.01%, MenuHost 0.00%, MenuBar 1.39%, Dock 2.34%, and
Awake 0.34%. Supervisor's retained observation removes the previously observed
healthy-process polling cost. All component handle counts ended between 230 and
607; Supervisor fell from 287 to 278 over the interval.

Raw evidence is retained in:

- `qa/performance/20260925-114547-hardening-baseline-summary.json`
- `qa/performance/20260925-123621-hardening-post-deploy-summary.json` and its CSV
- `qa/hardening-component-performance.json`

These results do not justify removing useful shell features. A future performance
pass should measure provider child-process cost and long-duration stability before
changing provider polling or deleting functionality.

## Evidence limits and remaining acceptance work

This makes the implementation more resilient; it does not guarantee compatibility
with future Windows or third-party changes. Physical monitor hot-plug, mixed-DPI
movement, sleep/resume, a second interactive Windows session, and interrupted
privileged promotion/rollback still need real environment testing.
The Windows computer-use API did not expose a targetable MacMakeover window after
deployment. Actual-desktop screenshot signoff is therefore still outstanding;
offscreen fixture inspection and profile geometry checks do not replace it.

Tailscale and Awake have known native-menu adapters. Unknown tray applications
remain visible/launchable when their registrations can be discovered, but there is
no universal native-menu protocol implemented for every application. MenuHost's
pipe is current-user restricted but is not named separately per interactive session.

Performance samples measure the named shell processes on a working desktop, not
all provider child-process cost. Short samples cannot prove absence of long-term
memory leaks or provide a controlled benchmark.
