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
- Keep the Apple menu protocol registered to `conhost.exe --headless` running `scripts/Show-MacAppleMenu.ps1` via `scripts/Install-AppleMenuHandler.ps1`; `wscript.exe`/VBS launchers are blocked by Defender/ASR on this PC, and direct PowerShell registration flashes a terminal window.
- Hot corners are handled by `scripts/start-hot-corners.ps1` through a current-user Startup shortcut. Tiny top-left/top-right click zones send Show Desktop; do not re-enable Seelen's invisible corner buttons because they steal Apple/menu-bar clicks.
- Do not restore RustDesk/Tailscale secrets from this repo. They are intentionally excluded.
- Verify visual changes with screenshots at 1280x800. Do not call visual work finished without visual QA.
- Treat delayed UI automations as reliability-critical: never chain one delayed UI task through another, verify the saved automation state after creating/updating it, and require a visible success/failure report after it fires.
