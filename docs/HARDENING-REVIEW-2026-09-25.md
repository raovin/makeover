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

## Evidence limits and remaining acceptance work

This makes the implementation more resilient; it does not guarantee compatibility
with future Windows or third-party changes. Physical monitor hot-plug, mixed-DPI
movement, sleep/resume, a second interactive Windows session, and interrupted
privileged promotion/rollback still need real environment testing.

Tailscale and Awake have known native-menu adapters. Unknown tray applications
remain visible/launchable when their registrations can be discovered, but there is
no universal native-menu protocol implemented for every application. MenuHost's
pipe is current-user restricted but is not named separately per interactive session.

Performance samples measure the named shell processes on a working desktop, not
all provider child-process cost. Short samples cannot prove absence of long-term
memory leaks or provide a controlled benchmark.
