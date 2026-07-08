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
- Keep the Control Center protocol registered to the fast MenuHost pipe launcher via `scripts/Install-MacControlCenterHandler.ps1`; the top-right sliders item opens `macmakeover-control-center:` directly and must not depend on pixel click zones. The handler writes `control` into `\\.\pipe\MacMakeover.MenuHost` and falls back to starting MenuHost with `--show control`.
- Keep Seelen WEG enabled for the visible bottom dock. Do not reintroduce `DockForm`, `SHAppBarMessage`, or any native MenuHost appbar dock; it interfered with maximize/work-area behavior.
- MenuHost popups must show without foreground activation (`WS_EX_NOACTIVATE` / `ShowWithoutActivation`). Do not call `form.Activate()` or `SetForegroundWindow(form.Handle)` for Apple/Control/Network/Bluetooth popups; native Alt+Tab must remain clean.
- Do not re-add `@seelen/tb-quick-settings` unless the user explicitly asks for the old Seelen flyout back.
- Hot corners are handled by `scripts/start-hot-corners.ps1` through a current-user Startup shortcut. The helper starts `tools/MacMakeover.MenuHost` and sends Apple/Control commands over a named pipe; keep the resident host running so clicks do not cold-launch. Tiny top-left/top-right click zones send Show Desktop; do not re-enable Seelen's invisible corner buttons because they steal Apple/menu-bar clicks.
- Do not restore RustDesk/Tailscale secrets from this repo. They are intentionally excluded.
- Verify visual changes with screenshots at 1280x800. Do not call visual work finished without visual QA.
- Treat delayed UI automations as reliability-critical: never chain one delayed UI task through another, verify the saved automation state after creating/updating it, and require a visible success/failure report after it fires.
