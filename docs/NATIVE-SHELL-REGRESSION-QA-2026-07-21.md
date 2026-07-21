# Native Shell Restart Regression QA - 2026-07-21

## Reported Failures

- Snipping Tool opened but its `New` action appeared unresponsive.
- The square managed wallpaper rendered in Fit mode with black side areas.
- The top AppBar could be covered while applications restored after sign-in.
- System memory was between 11 and 12 GB of 15.4 GB in use.

## Root Causes And Repairs

- A retired `start-hot-corners.ps1` process had been relaunched by an old Startup
  shortcut even though its scheduled task was disabled. The global mouse hook was
  stopped and the active shortcut removed. Promotion and live acceptance now reject
  either artifact; the native AppBar remains the sole owner of both corners.
- Snipping Tool's existing process was stale. Restarting only that process restored
  both `Ctrl+N` and an actual click on `New`; Windows recorded no application crash.
- The device-management ADMX policy was set to `3`, meaning KeepAspect/Fit. Earlier
  installer logic incorrectly used ordinary desktop value `10` inside ADMX data.
  ADMX requires `4` for CropToFit/Fill. The privileged repair now writes the correct
  value to both policy layers, preserves the managed image, refreshes the desktop,
  and installs a hidden logon/15-minute reconciliation task.
- The top AppBar now performs two bounded work-area reassertions while restored
  windows settle. It does not add a resident poller or window mover.
- Promotion now has a failure-recovery path. A cancelled UAC or failed privileged
  phase restarts Explorer to clear stale AppBar reservations, then relaunches exactly
  one copy of each native-shell process before returning the original error.
- The dock AppBar previously reserved only the size difference between the custom
  dock and the native taskbar. Hiding the native taskbar removes its reservation on
  this Windows build, leaving only 8/36 px. The dock now owns its complete visual
  height plus breathing room on every display: 56 logical px on the 150% laptop and
  84 physical px on the external display. The reservation no longer depends on the
  user's native-taskbar auto-hide preference.

## Live Verification

- Snipping Tool `New` opened the capture overlay after the stale process restart.
- A maximized Snipping Tool window left the menu bar visible.
- A real `Alt+Tab` from maximized Snipping Tool to Teams switched applications and
  left the menu bar and dock visible.
- Exactly one responsive MenuBar, MenuHost, and Dock remained after restart.
- The retired hot-corner process and active Startup shortcut were absent.
- MenuBar startup logs recorded both bounded AppBar reassertions on both displays.
- After an interrupted promotion left stale Explorer AppBar reservations, the first
  capture was rejected: the bars had been squeezed to 2 px and 11 px. Restarting
  Explorer cleared those reservations; the accepted follow-up shows full 30 px bars,
  edge-to-edge wallpaper, and a maximized window ending above the dock.

Local evidence is stored in `qa/incident-maximized-appbar-20260721.png` and
`qa/incident-alt-tab-appbar-20260721.png`. The post-recovery capture is
`qa/post-appbar-recovery-20260721.png`.

## Memory Finding

The observed 11-12 GB is high for an idle 16 GB system, but it did not come from
the custom shell. The three MacMakeover processes used about 213 MB combined working
set and 85 MB private memory in the later sample. The largest consumers were Chrome,
Teams and other WebView2 hosts, ChatGPT/Codex, Defender, service hosts, and Windows
memory compression. This is a workload/startup pressure issue, not evidence that the
native shell has returned to Seelen's resource cost.

## Privileged Acceptance Boundary

The first accepted privileged run changed both protected ADMX values from Fit (`3`)
to Fill (`4`) and installed the managed image, then failed while refreshing the
desktop because its dynamic interop class was not public. That defect is fixed and
preflight-gated. The wallpaper now passes visual inspection on both displays.

Subsequent UAC prompts timed out before execution. The elevated wallpaper guard is
therefore not registered, and Seelen's administrator-owned logon task is still
enabled even though its live processes have been stopped. These are the only two
remaining live-profile failures. The visible wallpaper and measured AppBar geometry
are fixed; sign-in durability remains unsigned until one privileged phase completes.
