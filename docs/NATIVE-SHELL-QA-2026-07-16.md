# Native Shell Visual QA - 2026-07-16

## Scope

Graphite typography and dock polish on the 1920x1200 laptop panel at 150% DPI.
The external LG display was not connected.

## Verified Live

- MenuBar and MenuHost publish in Release with zero warnings and zero errors.
- Manrope Regular/SemiBold and JetBrains Mono Medium are deployed beside the
  application and loaded privately; no system font installation is required.
- The 20 logical pixel AppBar reserves 30 physical pixels at 150% DPI.
- App label, telemetry, date, glyphs, separators, and battery share a coherent
  optical baseline with no clipping or overlap.
- Desktop, maximized, and restored-window screenshots retain the top and bottom
  work areas. No window is covered by the dock.
- Show Desktop was toggled to the real desktop and back without moving either bar.
- Sequential preflight and live-profile acceptance pass. The stateful audio tests
  must not be launched in parallel because each intentionally changes and restores
  master volume.
- Live memory at acceptance: MenuBar 69.3 MB and MenuHost 33.6 MB.

Local screenshot evidence is under `qa/graphite-*.png` and remains uncommitted by
repository policy.

## Pending Physical Gate

The graphite Windhawk definition is committed in
`config/windhawk/native-dock.json`, but its live HKLM settings were not updated:
Windows reported both UAC requests as cancelled. The currently visible dock is
therefore the previous opaque profile. Run the privileged promotion once, then
repeat the dock crop and mixed-DPI checks before calling that part signed off.

The follow-up dock geometry profile uses a 15-unit outer radius, moves the frame
down within its reserved strip, shifts only app/overlay/badge artwork by one unit,
and renders a two-unit native running indicator. These values require a fresh live
crop after privileged promotion; source-level validation alone is insufficient.
The source profile passed JSON parsing, selector assertions, dependency checks,
the pinned Windhawk binary hash check, and the MenuHost audio self-test. After the
cancelled promotion, the live registry still reported the previous 12-unit radius
and no custom running-indicator target; the live shell coherence test continued to
pass, confirming that the failed elevation attempts did not partially apply it.

Synthetic Alt+Tab was also rejected by the interactive desktop in this session:
the foreground handle did not change. Panel dismissal under a real Alt+Tab and
the disconnected external display therefore remain physical acceptance gates,
not inferred passes.
