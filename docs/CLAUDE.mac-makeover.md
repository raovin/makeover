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
- Keep the Apple menu protocol registered to `conhost.exe --headless` running `scripts/Show-MacAppleMenu.ps1` via `scripts/Install-AppleMenuHandler.ps1`; `wscript.exe`/VBS launchers are blocked by Defender/ASR on this PC, and direct PowerShell registration flashes a terminal window. This protocol is fallback plumbing only; normal Apple clicks are routed by `scripts/start-hot-corners.ps1` to the resident .NET MenuHost.
- Keep the Control Center protocol registered to the fast MenuHost pipe launcher via `scripts/Install-MacControlCenterHandler.ps1`; the top-right sliders item opens `macmakeover-control-center:` directly and must not depend on pixel click zones. The handler writes `control` into `\\.\pipe\MacMakeover.MenuHost` and falls back to starting MenuHost with `--show control`.
- Do not wire the Apple toolbar `onClick` directly to `macmakeover-apple-menu:`. Apple remains helper-routed; Control Center is the one intentional toolbar URI because the handler is a fast pipe echo, not the old PowerShell/WPF cold chain.
- Do not re-add `@seelen/tb-quick-settings` unless the user explicitly asks for the old Seelen flyout back.
- Hot corners are handled by `scripts/start-hot-corners.ps1` through a current-user Startup shortcut. The helper starts `tools/MacMakeover.MenuHost` and sends Apple/Control commands over a named pipe; keep the resident host running so clicks do not cold-launch. Tiny top-left/top-right click zones send Show Desktop; do not re-enable Seelen's invisible corner buttons because they steal Apple/menu-bar clicks.
- Do not restore RustDesk/Tailscale secrets from this repo. They are intentionally excluded.
- Verify visual changes with screenshots at 1280x800. Do not call visual work finished without visual QA.
- Treat delayed UI automations as reliability-critical: never chain one delayed UI task through another, verify the saved automation state after creating/updating it, and require a visible success/failure report after it fires.
