# Native Dock Expansion QA - 2026-07-18

## Change

The archived Seelen pin set contains 21 applications. Restoring that full set on
the 1280x800 logical laptop workspace caused Explorer to compact every taskbar
button inside the dock's former 120-unit side guards. The dock height had not
changed, but the smaller icons made the entire surface read as undersized.

The horizontal guard is now 24 units on each side. Vertical margins, 48-pixel
reserved work area, corner radius, opacity, button states, and pin set are
unchanged.

## Verified Live

- The laptop dock expanded from approximately 1,190 to 1,490 physical pixels.
- Explorer restored normal-size taskbar buttons without clipping overlays,
  indicators, or the outer dock corners.
- All 21 archived Seelen pins pass the live pin verifier.
- Maximized content stops above the dock and below the menu bar.
- The connected 1920x1080 external display reserves 20 logical pixels at the top
  and 48 at the bottom.
- A display hot-plug race was found during mixed-display QA. The menu bar now
  subscribes to display changes before its initial screen enumeration.
- Preflight, live-profile, Core Audio, pin-parity, and PowerShell parsing checks
  pass sequentially on both displays.

Local evidence is stored under `qa/dock-expanded-*-20260718.png` and remains
uncommitted by repository policy.
