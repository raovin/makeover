# Native Shell Mixed-DPI QA - 2026-07-20

## Scope

Live release QA with both displays connected: the 1920x1200 laptop panel at 150%
and the 1920x1080 external display at 100%. Evidence is under `qa/*final-20260720.png`
and remains local by repository policy.

## Visual Results

- The laptop keeps a 30 px menu bar and 72 px dock surface. Its work area reserves
  30 px above and 84 px below, leaving a 12 px physical gap above the dock.
- The external display uses a 25 px menu bar and 60 px dock surface. Its work area
  reserves 25 px above and 70 px below, leaving a 10 px physical gap above the dock.
- Both telemetry groups and dock frames are centered at physical x=960. Dock frame
  top/bottom margins have matching parity on both displays.
- Segoe UI Variable Text replaces the uneven private-font mix at 96 DPI. Labels,
  telemetry, date, separators, battery, and icons have no clipping or overlap.
- Packaged applications are resolved through their AppIds at high resolution.
  Claude uses the installed app's 300x300 logo rather than a blurry shell thumbnail.
- All 21 icons are alpha-validated and owner-drawn on the frame surface. No synthetic
  black slot backgrounds are present; the forced-hover capture enlarges and lifts the
  icon without painting the former grey rollover tile.
- Apple, Network, Bluetooth, and Control Center each rendered their independent
  panel without a console window, stale panel, or duplicate MenuHost process.

## Adversarial Results

- Three stop/start cycles restored exactly one responsive MenuBar, MenuHost, and
  Dock. The native taskbars reappeared while stopped and were hidden after restart.
- A second three-cycle dock-compositing pass kept all processes responsive, retained
  all 21 pins on both displays, matched the staged and deployed binaries, and logged
  no MacMakeover application errors.
- Eight rapid `WM_DISPLAYCHANGE` broadcasts preserved process identities and all
  processes stayed responsive. The bounded AppBar settling logic restored both work
  areas after Explorer's secondary taskbar completed registration.
- Two-way File Explorer to Chrome Alt+Tab switched the active application in both
  directions. The no-activation dock and tool windows did not enter the switcher.
- The MenuHost Core Audio self-test changed master volume, read it back, restored
  the original value, and passed. All 21 archived Seelen pins are still present.
- The profile installer was exercised from the normal user token. Its prior
  `OrderedDictionary.ContainsKey` compatibility failure is fixed and gated.
- A 30-second settled sample kept all processes responsive. Custom-shell CPU was
  0.57% median / 1.15% p95 of the 16-logical-processor machine; private memory was
  79.7 MB with a stable 235.1 MB aggregate working set.

## Remaining Privileged Gate

`WindhawkRunUITask` must be disabled by the elevated promotion phase. Windhawk's
service is stopped and manual and no Windhawk process is running, but an existing
administrator-owned scheduled task cannot be changed from the normal token. The
live profile test intentionally fails until the one UAC prompt is approved.
