# Claude Code Entry Point

Read `CODEX-HANDOVER.md` first. It contains the current live state of this Windows 11 macOS makeover project, including the Seelen UI config paths, safety rules, latest visual fixes, screenshots, backups, and remaining QA checklist.

Most important guardrails:

- Stop Seelen before editing its config/theme files.
- Do not restart Explorer while Seelen is running.
- Keep `settings_shortcuts.json` disabled so Alt+Tab and lock-screen input stay normal.
- Leave `Alt+Space` on PowerToys / Command Palette; do not bind it through Seelen.
- Hot corners are handled by the portable package under `C:\Users\VineethRao\source\repos\brunel\workspace\desktop\mac-makeover\scripts`.
- Verify every visual change with a fresh screenshot.
