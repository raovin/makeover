# Claude dock icon correction — 2026-09-25

The deployed Claude override is a 300×300 image whose visible artwork occupies
only coordinates (75,75) through (224,224). Scaling the whole image into the
28-logical-pixel dock slot made the visible tile approximately 14 pixels wide.
The earlier hardening review missed this asset-padding problem.

Override loading now finds nontransparent bounds, retains a small margin, and
scales the result into a square canvas while preserving aspect ratio and alpha.
Fully transparent overrides fall back to normal icon discovery. This work happens
when an icon is loaded, not during each repaint. Dock slot sizes are unchanged.

The existing Luna Max Dock task implemented the correction. Parent review covered
the full incremental diff and before/after images. Parent Release build and Dock
regression passed, including padded-square, rectangular, and transparent fixtures.
The published Dock artifacts were copied with matching hashes after graceful Dock
shutdown. Only Dock and Supervisor were restarted; Explorer and application
windows were not restarted. Backup:
`%LOCALAPPDATA%\MacMakeover\backups\claude-icon-20260925-154455`.

The deployed icon export was visually inspected at
`qa/claude-icon-deployed/Claude.png`; it fills the intended icon area. The deployed
shell profile passed. This verifies the actual deployed loader output, not an
actual-desktop screenshot.

## Separate Alt+Tab report

The user also reported missing Alt+Tab entries. The previous regression checked
menu dismissal, not completeness of Windows' switcher window list. Read-only
inspection found two virtual desktops. Windows reported Brave, ChatGPT, Claude,
and Teams main windows as shell-cloaked (DWM value 2), while both Chrome processes'
main windows were uncloaked. This is consistent with desktop filtering but does not
prove the cause without the user's missing-window examples.

No Alt+Tab or virtual-desktop preferences were changed. The user has been asked
which windows are missing and whether Alt+Tab should include both desktops.
Source inspection found no Dock code that changes other applications' window
styles or configures the Alt+Tab list; Dock's own window filtering is separate.
