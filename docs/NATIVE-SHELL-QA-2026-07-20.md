# Native Shell Mixed-DPI QA - 2026-07-20

## Scope

Live release QA with both displays connected: the 1920x1200 laptop panel at 150%
and the 1920x1080 external display at 100%. Evidence is under `qa/*final-20260720.png`
and remains local by repository policy.

## Visual Results

- The laptop keeps a 30 px menu bar and 72 px dock surface. Its work area reserves
  30 px above and 84 px below, leaving a 12 px physical gap above the dock.
- The external display uses the same 30 px menu bar and 72 px dock surface as the
  laptop. Its work area reserves 30 px above and 84 px below, leaving the same 12 px
  physical gap above the dock.
- Menu-bar typography, icon geometry, hit targets, and horizontal rhythm now match
  the laptop at physical size instead of shrinking to the former 25 px treatment.
- Dock frame, 42 px icons, 66 px slots, padding, curves, and running dots also match
  physically instead of using the cramped former 1.25x external-monitor exception.
- The production-only work-area AppBar stays behind the dock, preventing its 24 px
  external overlap from painting wallpaper across the tops of the icons.
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
- The native menu bar owns an eight-logical-pixel Show Desktop target at both top
  corners, matching the former Seelen interaction without a polling helper.
- The minimized-desktop pass uses the exact 6016 px `Big Sur (Day)` image recovered
  from the archived Seelen collection. Installer and live-profile checks compare its
  SHA-256 hash so the former generated gradient cannot replace it during upgrades.
  The installer also backs up and reconciles the MDM-mandated `DesktopPreto.png`
  target, then assigns the managed image to every Windows virtual desktop.
- Power telemetry now distinguishes `Battery`, `Charging`, and `Plugged in` from
  the real Windows power-line state. A separate label distinguishes `Power saver`,
  `Balanced`, and `High performance`; all three deterministic fixtures rendered
  without moving, clipping, or overlapping the right-side controls.
- The battery uses a clean filled icon when merely plugged in and a purpose-drawn
  vector bolt only while genuinely charging; no font glyph is squeezed into the icon.

## Adversarial Results

- Three stop/start cycles restored exactly one responsive MenuBar, MenuHost, and
  Dock. The native taskbars reappeared while stopped and were hidden after restart.
- A second three-cycle dock-compositing pass kept all processes responsive, retained
  all 21 pins on both displays, matched the staged and deployed binaries, and logged
  no MacMakeover application errors.
- Twenty-four rapid external-display samples had identical complete icon coverage.
  A cold-start comparison reached the stable 21-icon reference by 2.0 seconds and
  remained stable through the following 16 seconds of refresh cycles.
- Eight rapid `WM_DISPLAYCHANGE` broadcasts preserved process identities and all
  processes stayed responsive. The bounded AppBar settling logic restored both work
  areas after Explorer's secondary taskbar completed registration.
- Two-way File Explorer to Chrome Alt+Tab switched the active application in both
  directions. The no-activation dock and tool windows did not enter the switcher.
- The MenuHost Core Audio self-test changed master volume, read it back, restored
  the original value, and passed. All 21 archived Seelen pins are still present.
- The MenuBar power-state self-test passed the Windows AC/DC mode GUID mappings
  and all six source/mode labels. Preflight now rejects generic battery output,
  inferred 100%-charging state, or removal of the deterministic visual fixtures.
- The profile installer was exercised from the normal user token. Its prior
  `OrderedDictionary.ContainsKey` compatibility failure is fixed and gated.
- A 30-second settled sample kept all processes responsive. Custom-shell CPU was
  0.57% median / 1.15% p95 of the 16-logical-processor machine; private memory was
  79.7 MB with a stable 235.1 MB aggregate working set.
- The 6016 px wallpaper initially raised Dock working set to 230 MB because GDI+
  retained the full decoded bitmap. The dock now keeps a high-quality display-sized
  copy; two cold promotion cycles passed at 94-109 MB, and preflight rejects a return
  to full-source decoding.

## Privileged Promotion

The elevated promotion completed successfully. It preserves the protected MDM
policy while replacing its local `DesktopPreto.png` target with a managed Big Sur
derivative and changing that provider's local style to edge-to-edge Fill; rollback
restores both the backed-up image and provider value. It also disables the
administrator-owned Windhawk and hot-corner startup paths and leaves no Seelen,
Windhawk, or YASB process active.
