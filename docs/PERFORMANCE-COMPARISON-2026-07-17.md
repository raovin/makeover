# Native Shell vs Seelen UI Performance - 2026-07-17

## Method

- Same Windows session, 1920x1200 laptop display, 150% scaling, 16 logical CPUs.
- Each profile received a 35-second settling period after activation.
- Idle sampling ran for 90 seconds at one-second intervals; the first five samples
  were excluded from percentile calculations.
- Interaction sampling used 25 real Alt+Tab transitions from the same Chrome
  window while a 45-second process sampler ran.
- Custom-process totals include `seelen-ui` plus `slu-service`, or
  `MacMakeover.MenuBar` plus `MacMakeover.MenuHost`. Shell totals add Explorer and
  DWM.
- System-wide CPU and available-memory values are contextual only because Teams,
  Chrome, Codex, and other work applications remained open and changed activity.

Raw CSV and JSON evidence is generated under `qa/performance/` and intentionally
ignored by Git. Reproduce it with `scripts/Measure-ShellPerformance.ps1`.

## Results

| Metric (median) | Seelen UI | Native shell | Native difference |
|---|---:|---:|---:|
| Custom working set, idle | 227.1 MB | 102.6 MB | 54.8% lower |
| Custom private memory, idle | 69.4 MB | 33.1 MB | 52.3% lower |
| Custom threads, idle | 113 | 23 | 79.6% lower |
| Custom handles, idle | 1,387 | 648 | 53.3% lower |
| Shell working set, idle | 511.9 MB | 351.8 MB | 31.3% lower |
| Shell private memory, idle | 215.2 MB | 175.9 MB | 18.3% lower |
| Custom CPU, idle | 0.000% | 0.667% | native is higher |
| Custom CPU p95, idle | 0.193% | 1.321% | native is higher |
| Custom working set, Alt+Tab | 228.0 MB | 103.0 MB | 54.8% lower |
| Custom threads, Alt+Tab | 118 | 24 | 79.7% lower |
| Custom handles, Alt+Tab | 1,400 | 646 | 53.9% lower |
| Alt+Tab automation median | 159 ms | 165 ms | effectively tied |
| Alt+Tab automation maximum | 1,203 ms | 982 ms | native 18.4% lower |

Both profiles kept their expected processes present and responsive throughout the
accepted samples. The automation timings include Computer Use and window activation
overhead, so the six-millisecond median difference is not meaningful.

## Reliability Findings

- Seelen started a fourth top-level window titled `Widget Error` alongside its
  dock, toolbar, and flyout host. The visible message reported that the Flyouts
  widget had stopped responding too many times.
- Seelen did not restart during the 25-transition Alt+Tab stress loop, but its first
  measured transition took 1.203 seconds.
- The native shell completed the same loop without a process restart or error
  window. Its first transition took 0.982 seconds.
- The native profile was restored after testing: Seelen and its service are stopped,
  the Seelen scheduled task is disabled, and both native processes are running.

## Verdict

Keep the native shell as the production profile. It removes roughly half of the
custom memory and handles and about four-fifths of the custom thread count while
retaining normal Explorer taskbar and Alt+Tab behavior. Seelen remains useful only
as an archived rollback/reference profile.

The native shell is not finished from a performance perspective: its 1.5-second
telemetry poll invalidates the full menu bar and produced a repeatable 0.67% median
CPU load across 16 logical processors. The next optimization should cache stable
layout and app labels, repaint only changed regions, and decouple CPU/network
sampling from full-bar painting. That work should be benchmarked independently so
visual behavior is not traded for an unmeasured CPU improvement.
