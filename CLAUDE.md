# Claude Code Entry Point

This folder is the single home and source of truth for the Windows macOS makeover.

Start here:

1. `docs/CODEX-HANDOVER.md`
2. `README.md`
3. `scripts/verify.ps1`
4. `config/seelen`

The active user goal is continued beautification, not a from-scratch rebuild. The latest handoff has the current Apple-menu behavior, visual QA paths, Git commit, and suggested next polish passes.

Guardrails:

- Stop Seelen before editing or restoring its config.
- Keep `settings_shortcuts.json` disabled unless the user explicitly wants to revisit shortcuts.
- Leave `Alt+Space` on PowerToys / Command Palette; do not bind it through Seelen.
- Keep Apple-menu clicks item-owned from the toolbar: `onClick: open("macmakeover-apple-menu:")`. The protocol must use the fast resident MenuHost pipe path (`conhost --headless cmd /c echo apple> \\.\pipe\MacMakeover.MenuHost || start MenuHost --show apple`). Do not route Apple clicks through broad helper pixel zones; that can fire while clicking maximized app chrome.
- The Control Center opens via the sliders item's `onClick: open("macmakeover-control-center:")`. That protocol (registered by `scripts/Install-MacControlCenterHandler.ps1`) uses `conhost --headless cmd /c echo control> \\.\pipe\MacMakeover.MenuHost` with a `|| start MenuHost --show control` fallback - fast (~300ms), position-independent, and self-healing. Do NOT route Control Center through pixel click zones in the helper: bar item widths drift (badge digits, date length) and the zones silently break.
- Keep Seelen WEG enabled for the visible bottom dock. Do not reintroduce `DockForm`, `SHAppBarMessage`, or any native MenuHost appbar dock; it interfered with maximize/work-area behavior.
- MenuHost popups must show without foreground activation (`WS_EX_NOACTIVATE` / `ShowWithoutActivation`). Do not call `form.Activate()` or `SetForegroundWindow(form.Handle)` for Apple/Control/Network/Bluetooth popups; native Alt+Tab must remain clean.
- UX model for the top bar: informational readouts (CPU, MEM, NET, battery) live in the CENTER cluster and are not clickable; interactive controls live on the RIGHT and each opens its own distinct surface (Network popup, Bluetooth popup, Control Center, calendar, notifications). Never give several icons the same target.
- Do not re-add `@seelen/tb-quick-settings` unless the user explicitly asks for the old Seelen flyout back.
- Hot corners are handled by `scripts/start-hot-corners.ps1` through a current-user Startup shortcut. Keep dwell actions disabled (`topLeft/topRight/bottomLeft/bottomRight = None`) and keep only the tiny top-left/top-right click zones for Show Desktop. Do not add background window nudging or broad top-bar pixel routing.
- If a stale maximized app is still behind the dock, run `scripts/fit-windows-to-workarea.ps1`. It repairs each candidate against that window's own monitor work area. Keep it one-shot; do not reintroduce a background window mover.
- Do not restore RustDesk/Tailscale secrets from this repo. They are intentionally excluded.
- Verify visual changes with screenshots at 1280x800. Do not call visual work finished without visual QA.
- Treat delayed UI automations as reliability-critical: never chain one delayed UI task through another, verify the saved automation state after creating/updating it, and require a visible success/failure report after it fires.
