# Native Menu Bar Tray Apps QA - 2026-07-22

## Defect

Tray-first programs have no taskbar-eligible window, so they correctly stay out of
the dock. The native replacement menu bar did not yet mirror Windows notification
icons, however, leaving apps such as Awake & Available running without a visible
control surface.

## Resolution

- Read registered Windows notification icons and match them to live executable paths.
- Exclude shell-owned system icons already represented by menu-bar controls.
- Render every live app extra inline immediately left of the connection control; the
  production display widths do not require a secondary overflow interaction.
- Prefer the executable's full-quality icon and use Windows' saved tray snapshot as
  a fallback.
- Show the app name on hover and activate its existing window or executable on click.
- Awake & Available now signals its existing instance to open the real context menu;
  repeat launches no longer show an "already running" message box.
- Live process matching performs one process-table pass every five seconds instead of
  one enumeration per registered icon, avoiding a high-frequency cost on the
  1.5-second telemetry refresh.
- `--snapshot-tray <path>` provides deterministic regression evidence.

## Gates

- MenuBar and Awake & Available builds use warnings as errors.
- The snapshot includes the live Awake & Available registration and executable.
- Mixed-DPI preview is checked for baseline, spacing, clipping, and icon fidelity.
- Production click QA must open the Awake & Available control menu without creating a
  second process or a message box.
- Baseline comparison: committed MenuBar `1a1608e` used 4.30 CPU seconds over 30
  seconds; the final tray-aware preview used 4.94. The 0.64-second delta is bounded,
  and both remained responsive without handle growth.

## Production Evidence

- Exactly one production MenuBar process renders both active displays.
- Native profile passes with MenuBar below its 100 MB gate (78.7 MB after warm-up
  while rendering both active displays).
- Awake & Available appears in the menu-bar extras snapshot and remains absent from
  the dock snapshot while it has no taskbar window.
- Launching Awake & Available again keeps one process and opens an accessible control
  menu containing sleep prevention, Teams activity, interval, safety, and exit actions.
- The companion source is tracked at `tools/AwakeAndAvailable`, built by the native-shell
  release, deployed to `%LOCALAPPDATA%\MacMakeover\bin`, registered at logon, and verified
  as exactly one process from that managed path. The former sibling build remains backed up.
- Mixed-DPI production screenshot: ignored QA artifact
  `qa/tray-integration-final-production-20260722.png`.
- Final network isolation recorded 30/30 replies from the gateway, Cloudflare, and Google
  DNS targets, ten successful DNS lookups, successful HTTPS through Proton VPN, and no
  Wi-Fi reset/error events. A 60-second four-process soak found no restart, hang, or
  sustained handle, thread, or working-set growth.
- Clicking the former overflow exposed a WinForms disposal race in the old release: its
  `ContextMenuStrip` could dispose while the modal menu filter was still closing it. The
  inline-all design removes both the extra click and that failure path. A preflight source
  gate rejects any return of the three-item cap or overflow control.
