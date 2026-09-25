# Claude Code Entry Point

This repository is the source of truth for the native Windows macOS makeover.

Read first:

1. `README.md`
2. `docs/NATIVE-SHELL-ARCHITECTURE.md`
3. `docs/NATIVE-SHELL-QA-2026-07-16.md`
4. `scripts/Test-NativeShellPreflight.ps1`

## Production Architecture

- `MacMakeover.MenuBar` owns the top AppBar.
- `MacMakeover.MenuHost` owns Apple and system panels.
- `MacMakeover.Dock` owns the visible dock and pin actions.
- Windows Explorer owns Alt+Tab, native taskbar state, and window lifecycle.
- Windhawk's Taskbar Styler is disabled in production and retained for rollback.
- Seelen UI is not part of production. Its last known profile and historical notes
  live under `archive/seelen-ui/` for optional rollback research.

## Guardrails

- Do not start, install, or re-enable Seelen while testing the production profile.
- Do not add polling window movers, replacement task switchers, global key hooks,
  or taskbar z-order loops.
- Keep `Alt+Space` on Command Palette / PowerToys Run.
- One top-bar control opens one intended surface. Network and Bluetooth remain
  independent; telemetry remains informational.
- Preserve Explorer's native taskbar pin state and window lifecycle; keep native
  taskbar behavior available when the custom Dock exits.
- Visual changes require real desktop captures in restored and maximized states.
- Exercise real Alt+Tab after shell, work-area, or dock changes.
- Run both native-shell tests before declaring completion.
- Do not restore RustDesk, Tailscale, browser, or work-account secrets from Git.
- The external display needs a physical mixed-DPI check whenever it is connected.

## Verification

```powershell
.\scripts\Test-NativeShellPreflight.ps1 -SkipDownloadCheck
.\scripts\Test-NativeShellProfile.ps1
```

The current production installer is `scripts/Promote-NativeShell.ps1`. The Seelen
archive is deliberately isolated and must not be treated as a current handover.
