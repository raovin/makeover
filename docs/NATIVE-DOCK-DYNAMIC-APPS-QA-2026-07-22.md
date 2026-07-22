# Native Dock Dynamic Apps QA - 2026-07-22

## Defect

The native dock rendered only the 21 pinned launchers. Its timer updated running dots
for known pinned process names but never enumerated taskbar windows, so an unpinned app
such as Microsoft Edge could be open without appearing in the dock.

## Resolution

- Enumerate visible taskbar-eligible top-level windows once per second.
- Group conventional apps by executable and append one transient item per app.
- Separate `ApplicationFrameHost` surfaces by title and remove duplicate host entries.
- Remove a transient item after its last qualifying window closes.
- Preserve all pinned items and contract slot spacing when a busy dock nears a display edge.
- Expose `--snapshot-running <path>` for deterministic profile validation.

## Production Evidence

- Microsoft Edge appeared as one item despite its multi-process tree.
- Notepad appeared as `Notepad`, not `Notepad.exe`.
- Settings appeared exactly once through `ApplicationFrameHost`.
- Edge, Settings, Snipping Tool, and a local utility coexisted without clipping on the
  1920x1200 150% laptop display and the 1920x1080 external display.
- Closing the QA Edge and Settings windows removed both items within five seconds.
- All 21 archived Seelen pins remained present and in their original order.

Screenshots are captured under the ignored `qa/` directory:

- `dynamic-dock-final-production-20260722.png`
- `dynamic-dock-multi-app-production-20260722.png`
- `dynamic-dock-after-removal-production-20260722.png`

## Gates

- Release build: zero warnings and zero errors.
- Dock self-test and PowerShell parser: pass.
- Native profile, preflight, and 21-pin checks: pass.
- System reliability: pass; only the separately tracked staged BIOS update remains.
- 60-second soak: 1.47 CPU seconds, 114.3-115.1 MB working set, no sustained handle,
  thread, private-memory, or working-set growth.
