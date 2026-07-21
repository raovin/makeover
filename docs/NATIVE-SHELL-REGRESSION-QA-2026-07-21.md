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

## Live Verification

- Snipping Tool `New` opened the capture overlay after the stale process restart.
- A maximized Snipping Tool window left the menu bar visible.
- A real `Alt+Tab` from maximized Snipping Tool to Teams switched applications and
  left the menu bar and dock visible.
- Exactly one responsive MenuBar, MenuHost, and Dock remained after restart.
- The retired hot-corner process and active Startup shortcut were absent.
- MenuBar startup logs recorded both bounded AppBar reassertions on both displays.

Local evidence is stored in `qa/incident-maximized-appbar-20260721.png` and
`qa/incident-alt-tab-appbar-20260721.png`.

## Memory Finding

The observed 11-12 GB is high for an idle 16 GB system, but it did not come from
the custom shell. The three MacMakeover processes used about 213 MB combined working
set and 85 MB private memory in the later sample. The largest consumers were Chrome,
Teams and other WebView2 hosts, ChatGPT/Codex, Defender, service hosts, and Windows
memory compression. This is a workload/startup pressure issue, not evidence that the
native shell has returned to Seelen's resource cost.

## Privileged Acceptance Boundary

The code, build, self-tests, preflight, input-hook removal, and AppBar checks passed.
The live machine still needs one accepted UAC promotion before the protected ADMX
provider changes from Fit (`3`) to Fill (`4`) and the wallpaper guard is registered.
Until that happens, the wallpaper portion of the live profile is not signed off.
