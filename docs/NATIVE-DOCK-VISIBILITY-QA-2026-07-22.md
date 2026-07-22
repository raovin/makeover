# Native Dock Visibility Recovery QA - 2026-07-22

## Symptom

Both dock surfaces appeared to disappear while the `MacMakeover.Dock` process remained
running and responsive. A subsequent desktop capture showed that the windows recovered
without a process restart, identifying an intermittent visibility/z-order loss rather
than a crash or missing startup entry.

## Gap

The existing 1.5-second shell guard repaired hidden Windows taskbars and bottom AppBar
reservations, but it never checked the two visual `DockForm` windows. A live profile could
therefore pass on process and work-area health while a dock surface was hidden.

## Repair

- Extend the existing guard to inspect every dock surface.
- Re-show and restore topmost state without activating the dock when it is hidden or
  loses its topmost style.
- Re-raise it when a fullscreen foreground window covers its entire monitor and sits
  above the dock in z-order.
- Avoid repeated z-order calls after the dock is already above that window.
- Require one visible, topmost, full-width dock surface per active display in live
  profile acceptance.
- Add a preflight source gate for the visibility repair path.

## Adversarial Acceptance

- Forcibly hid one production dock HWND; the guard restored it within two timer cycles.
- Forcibly removed that HWND from the topmost band; the guard restored it.
- Both mixed-DPI work areas retained their bottom reservations.
- Native-shell profile and preflight passed with two real dock surfaces.
- Final 30-second soak: no restart, hang, handle growth, thread growth, or working-set
  growth; dock CPU use was 0.58 seconds.
- Final ignored visual artifact: `qa/dock-visibility-guard-final-20260722.png`.
