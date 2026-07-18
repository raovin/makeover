# Native Dock Polish QA - 2026-07-18

## Visual Corrections

- Replaced the flat black dock fill with a fully opaque, restrained graphite
  gradient. Maximized application content cannot show through the dock.
- Increased the shell radius to 14 units and added a graduated one-pixel border
  so all four corners remain legible against dark windows and wallpaper.
- Reduced the unused top band while retaining the native 48-unit reserved work
  area. The dock remains available when applications are maximized.
- Fixed the icon artwork at 26 units and gave task buttons a 42-unit minimum
  width. Explorer can no longer silently compact the full pin set after restart.
- Normalized hover, active, and pressed backgrounds; reduced running indicators;
  and scaled application presence and notification overlays independently.

## Adversarial Checks

- Captured the complete virtual desktop and a full-resolution primary-display
  crop after Explorer restart.
- Maximized and restored Snipping Tool while observing the primary dock.
- Confirmed the dock remained visible, opaque, centered, and unclipped in the
  maximized state.
- Exercised native Alt+Tab from a normal application and confirmed foreground
  ownership changed to Windhawk without a custom task switcher.
- Confirmed Explorer, MenuBar, and MenuHost remained responsive after the state
  transitions.
- Confirmed all 21 archived Seelen pins are present.
- Confirmed the live Windhawk values match the repository profile.

Local evidence is stored under `qa/dock-live-*-20260718.png` and remains
untracked by repository policy.
