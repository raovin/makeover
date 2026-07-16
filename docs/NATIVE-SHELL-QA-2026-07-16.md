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

The geometry profile was subsequently promoted successfully. A first live capture
confirmed that normal maximized windows still stop at the 48-logical-pixel reserved
taskbar strip and that icon, overlay, badge, and running-indicator content is no
longer clipped. The follow-up contrast pass increases the top inset by one unit and
uses an opaque outline because the translucent border blended into dark windows.
Both the maximized dark-window capture and the desktop-wallpaper capture show all
four corners and complete icon artwork. Show Desktop must settle for six seconds
before capture: its transition temporarily collapses the DirectComposition icon
surfaces into thin fragments even though the stable state renders correctly.

A later real Alt+Tab into maximized Codex reproduced a separate z-order failure:
Codex was `IsZoomed=true` with normal caption/thick-frame styles, but its outer
rectangle covered the monitor, so Explorer removed `WS_EX_TOPMOST` from
`Shell_TrayWnd`. The resident MenuBar now restores that flag for normal/maximized
windows and stands down for genuine borderless fullscreen.

Live adversarial acceptance explicitly demoted `Shell_TrayWnd` with
`HWND_NOTOPMOST`; the resident guard restored `WS_EX_TOPMOST` within 1.2 seconds
and logged the recovery. The profile test now repeats this probe and restores the
taskbar itself before failing, so a broken guard cannot leave the dock hidden.

Synthetic Alt+Tab was also rejected by the interactive desktop in this session:
the foreground handle did not change. Panel dismissal under a real Alt+Tab and
the disconnected external display therefore remain physical acceptance gates,
not inferred passes.
