# Native Shell Regression QA - 2026-07-22

## Wallpaper seam

The visible split above the dock was caused by two custom windows repainting an
approximation of Windows' Fill wallpaper crop. Once the dock began reserving its full
height, the mismatched synthetic strip became visible across the display.

The production dock now:

- records the complete dock height plus 8 px gap with Explorer through `ABM_SETPOS`;
- keeps only a transparent, nonpainting 1 px AppBar anchor on screen;
- no longer creates a full-width `DockBackdropForm`;
- leaves the real Windows desktop visible everywhere outside the rounded dock frame.

## Verification

- PowerShell parser: all repository scripts passed.
- Release build: zero warnings and zero errors.
- Native-shell preflight: passed with both displays detected.
- Laptop work area: 20 px top and 56 px bottom reservation.
- External work area: 30 px top and 84 px bottom reservation.
- Runtime soak: exactly one responsive Dock process; no Seelen, SLU, or YASB process.
- Visual desktop pass: wallpaper remained continuous through both lower display edges.
- Visual maximized-window pass: the application stopped above the dock and retained
  the intended breathing room.

The full profile audit still reports privileged machine-state work unrelated to this
rendering fix: Seelen's scheduled logon task is enabled, MDM has reapplied wallpaper
style `3` at both active and provider layers, and the wallpaper repair task is absent.
The current desktop remains visually filled, but those items require the pending
elevated promotion to make the state durable across future logons and MDM refreshes.
