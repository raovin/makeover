# Deployment and performance review — 2026-09-25

## Deployment result

Source commit `d65e6b5` was pushed on `codex/native-tray-audit`. The promoter
published and installed the binaries and matching deployment manifest, registered
the user profile, and passed static preflight. Its privileged phase stopped at an
inaccessible UAC prompt. The waiting promoter was stopped; Explorer and the five
custom shell components were restored through their existing scheduled tasks.
The UAC prompt subsequently cleared. The privileged phase was not rerun; the
September 3 success marker was not used as evidence of a new privileged run.

The resulting installation passed `Test-NativeShellProfile.ps1`, including
running executable hashes, and `Test-NativeTaskbarPins.ps1` (all 21 archived pins).
The new binaries are running. This was a binary upgrade using the existing
privileged configuration, not a completed end-to-end privileged promotion.

## Measurements

A 30-second sample of the previous running binaries gave these CPU averages,
expressed as percent of one logical CPU core, and endpoint private memory:

| Component | CPU, one core | Private MB |
| --- | ---: | ---: |
| Supervisor | 9.83% | 27.5 |
| MenuBar | 1.87% | 33.9 |
| Dock | 1.61% | 56.8 |
| Awake | 0.16% | 28.4 |
| MenuHost | 0.00% | 8.9 |

After deployment, `Measure-ShellPerformance.ps1 -Profile post-deploy-review
-DurationSeconds 30` reported all five expected processes present and responsive.
Across 16 logical processors, the custom components used median 1.084% total CPU
(p95 1.664%), median 130.57 MB private memory, and 334.438 MB working set. The
script excluded its first five samples from summary statistics.

These are short desktop samples with background activity, not a controlled
before/after benchmark or proof of a memory leak. Child CLI processes used for
provider queries are not included in the named custom-process totals. Raw
evidence remains in the ignored `qa` directory.

## Recommended changes, in order

1. **Remove repeated healthy-process enumeration from Supervisor.** Its main loop
   checks four process names every 500 ms, plus Explorer every five seconds.
   Keep crash recovery, session isolation, and failure backoff. Discover processes
   together, retain their lifetime handles, and wait for exits; rediscover only
   when a process is missing or a retry is due. Dispose signaled handles before
   waiting again and handle multiple matching processes and PID reuse. Validate
   recovery and compare longer steady-state CPU samples before deployment.
2. **Reduce tray scanning work.** `TrayAppProvider.Capture` scans all processes and
   reads their main modules, while registry capture rereads metadata and icon
   bytes on its two-second cache interval. Filter candidates before path queries,
   use a lightweight image-path query, cache version metadata by executable file
   identity, and consider registry change notifications. Preserve live GUID
   validation, blank-tooltip fallbacks, and icon-change repainting.
3. **Share Dock state capture across displays.** Each Dock form requests a process
   and window snapshot every second. One coordinator could feed all displays.
   This is primarily a multi-monitor improvement; the measured desktop had one
   display. Preserve pin reload generations and window activation behavior.
4. **Make provider allowance polling configurable.** Grok starts an authenticated
   agent subprocess for each read, and provider cadence is two minutes. Consider
   opt-out or a slower refresh with manual refresh retained. Measure subprocess
   CPU and wakeups before choosing a default. Gemini background polling is already
   disabled; removing its UI placeholder alone would not establish a CPU saving.

Grok CLI and AGY CLI independently reviewed the supplied source. Both prioritized
Supervisor polling. Their performance predictions were treated as hypotheses;
only the measurements above are observed costs.

## What to retain

Keep Supervisor recovery and its backoff, MenuHost, Awake, and native tray menus.
The evidence supports removing redundant background work before removing useful
features. MenuHost was effectively idle and Awake inexpensive in the short
sample. Cosmetic LINQ rewrites and deleting archived files are lower priority
than the recurring scans and do not have demonstrated runtime savings.

No performance feature was removed in this review. These recommendations require
implementation and validation as a subsequent change.
