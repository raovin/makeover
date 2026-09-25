# MenuBar and MenuHost source audit — 2026-09-25

## Task record

- Task ID: `01a0d82a-b257-7f13-80a8-777dc7be63c1`
- Objective: audit the native menu/tray implementation and apply bounded, source-level reliability, performance, lifecycle, IPC, and layout fixes within `tools/MacMakeover.MenuBar/**` and `tools/MacMakeover.MenuHost/**`.
- Worktree: `C:\Users\VineethRao\.codex\worktrees\2a86\mac-makeover`
- Starting ref: `4a2b45baf8564799fe45ec7eb9373c91e872d356` (`Record deployed shell verification and performance review`)
- Starting branch state: detached `HEAD`; local ref `codex/native-tray-audit` pointed at the starting ref. The `main` ref at audit start was `3052e505`.
- Scope: source/config/assets and the audit record only. No deployment, registry/settings mutation, VPN operation, production process termination, or external send was performed.

## Reviewed inventory

The required root and shell contracts were read before editing:

- `README.md`
- `docs/NATIVE-SHELL-KNOWN-QUIRKS.md`

The related audit/performance context was also reviewed:

- `docs/NATIVE-SHELL-TRAY-AUDIT-2026-09-24.md`
- `docs/PERFORMANCE-REVIEW-2026-09-25.md`

Every file currently present under the owned implementation directories was inventoried:

### `tools/MacMakeover.MenuBar`

- `AiProviderUsage.cs`
- `app.manifest`
- `MacMakeover.MenuBar.csproj`
- `MenuBarForm.cs`
- `NativeMethods.cs`
- `Program.cs`
- `SystemState.cs`
- `TrayApps.cs`
- `Typography.cs`
- Assets: `Assets/apple-mark.png`, `Assets/Claude-Mark-32.png`, `Assets/Grok-Mark-144.png`, `Assets/OpenAI-Blossom.svg`, `Assets/Provider-Mark-Sources.md`, and the bundled font files/license notices under `Assets/Fonts/`.

### `tools/MacMakeover.MenuHost`

- `MacMakeover.MenuHost.csproj`
- `Program.cs`

The asset and project files were reviewed as build/runtime inputs; no asset or project-file change was needed.

## Findings and bounded fixes

### Tray discovery and metadata

1. `TrayAppProvider.Capture()` previously enumerated all processes and attempted `MainModule` access before it knew whether a process name could match a registered tray executable. The capture path now takes one `Process.GetProcesses()` snapshot per capture, filters by candidate `ProcessName` before reading `MainModule`, validates normalized executable paths against registered candidates, and disposes every process wrapper. `TrayAppProviderSelfTest()` supplies a snapshot delegate and asserts the enumeration seam is called exactly once.

2. Repeated `FileVersionInfo` reads could add avoidable metadata I/O during tray refreshes. Version metadata is now cached by the existing source identity, with a bounded 64-entry cache and negative results cached as well. This is a bounded optimization, not a claim of a controlled CPU benchmark improvement.

3. A malformed or stale registry row could abort the entire tray-registration pass. Each row is now isolated behind a recoverable exception boundary so the remaining registrations can still be captured.

### Tray layout and native dispatch

4. A large tray set, narrow bar, or high-DPI scale could push icons beyond the drawable area. Tray layout is now computed by a pure `ComputeTrayLayout` helper. Visible icons fit the available region and the remainder is represented by a bounded `+N` overflow button/menu. The overflow menu exposes each hidden app's validated `Open` action and only offers `Show native menu` when the existing app-specific native dispatch contract recognizes the app. No generic fabricated shell menu was introduced.

5. Tight layouts compact the calendar label to `HH:mm` only when the tray projection needs the space. The active-app label also receives a bounded width on narrow bars. The no-app and zero-width cases have explicit fallback behavior rather than relying on an offscreen draw.

6. Existing native contracts were preserved: live tray rectangles still require `Shell_NotifyIconGetRect`; Tailscale still uses its known adapter/dispatch path; unknown apps do not receive synthetic native-menu behavior.

### Lifecycle, threading, and resource safety

7. Display-setting notifications could race rebuild/dispose work against the `_bars` collection. `MenuBarContext` now protects the collection with a gate, snapshots it before UI-thread teardown, and handles partial rebuild failure. The pending-rebuild flag uses volatile access.

8. The delayed app-bar reassertion now uses the form lifetime cancellation token and handles cancellation, preventing startup work from outliving the form.

9. Managed disposal is idempotent in `MenuBarForm`; the `BeginManagedDispose` guard is exercised twice by the MenuBar self-test. Offscreen bitmap rendering cleans up a bitmap if rendering fails, and the SVG parser disposes a partially-created path on its unexpected-exception path.

10. `SystemStateProvider` now guards start/dispose transitions and disposed polling/event paths against duplicate lifecycle calls and late callbacks.

### MenuHost IPC and command scheduling

11. The named-pipe server previously had unbounded line-read/idle exposure. Commands are now normalized against a five-command allowlist, limited to 64 characters, read through a bounded reader, and given a 750 ms per-client idle timeout. Both server and client use `PipeOptions.CurrentUserOnly`.

12. Invalid commands are rejected before queueing or logging. The pending command queue is deduplicated and capped at eight entries. Drain work processes one command per 10 ms WinForms timer tick. `BeginInvoke` is used only once to arm that timer; remaining work does not recursively enqueue marshaled callbacks, allowing the UI message loop to yield under command flood.

13. A real double-dispose regression was found in the first MenuHost regression run: disposing the context twice could dispose its cancellation source twice. The context now has an idempotent managed-dispose guard. The regression suite also exercises the server using a unique isolated pipe name, so the production pipe is not touched.

## Judgment calls and preserved behavior

- Kept the existing live GUID validation and native tray hit-testing contracts rather than broadening them to guessed shell behavior.
- Kept Tailscale as the explicitly known native-dispatch adapter; did not invent a generic native-menu protocol for arbitrary tray apps.
- Kept Gemini background polling disabled as an intentional provider-load choice.
- Did not modify Supervisor, Dock, deployment, or unrelated shell code outside the requested owned paths.
- Used a bounded overflow menu and compact calendar text as the least invasive response to constrained geometry.
- Used synthetic/offscreen rendering for QA. This proves deterministic layout behavior for the named fixtures but does not prove physical mixed-DPI, hotplug, AppBar, or live-window behavior.

## Verification

The following checks completed successfully in this worktree:

```text
dotnet restore tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj
dotnet restore tools/MacMakeover.MenuHost/MacMakeover.MenuHost.csproj

dotnet build tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --configuration Release --no-restore
dotnet build tools/MacMakeover.MenuHost/MacMakeover.MenuHost.csproj --configuration Release --no-restore
```

Both Release builds completed with 0 warnings and 0 errors.

```text
dotnet run --project tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --configuration Release --no-build -- --self-test
dotnet run --project tools/MacMakeover.MenuHost/MacMakeover.MenuHost.csproj --configuration Release --no-build -- --self-test
dotnet run --project tools/MacMakeover.MenuHost/MacMakeover.MenuHost.csproj --configuration Release --no-build -- --regression-test
```

All three commands exited 0. The MenuHost regression includes unique-pipe coverage for idle clients, a valid command after idle timeout, invalid input, oversized input, and a command flood; it asserts the queue remains bounded. It also runs an isolated STA UI loop with an injected no-op command handler and a WinForms heartbeat timer, confirming heartbeat progress while a producer floods valid commands without opening real menus.

The offscreen fixture command also exited 0:

```text
dotnet run --project tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --configuration Release --no-build -- --render-qa tools/MacMakeover.MenuBar/qa/offscreen-2026-09-25
```

Generated and visually inspected synthetic fixtures:

- `normal-1280-11.png`
- `narrow-800-11.png`
- `highdpi-1280-11.png`
- `highdpi-1280-32.png`
- `manifest.json`

The 32-app high-DPI fixture visibly shows a `+23` overflow affordance with no overlap in the rendered frame. The fixtures are offscreen PNGs only; no live window was shown.

`git diff --check` completed without whitespace errors.

## Git handoff

- Modified implementation files: `tools/MacMakeover.MenuBar/MenuBarForm.cs`, `Program.cs`, `SystemState.cs`, `TrayApps.cs`, and `tools/MacMakeover.MenuHost/Program.cs`.
- Added this audit record: `docs/AUDIT-MENUS-2026-09-25.md`.
- Generated QA PNGs remain under `tools/MacMakeover.MenuBar/qa/offscreen-2026-09-25/` and are ignored by the repository's `qa/` rule.
- No commit was created, no branch was pushed, and no pull request was opened.

## Gaps and follow-up recommendations

- No live AppBar/window, physical multi-monitor mixed-DPI, display hotplug, or tray-rectangle acceptance run was performed.
- No controlled before/after CPU or allocation benchmark was run; the process-discovery improvement is evidenced by the one-snapshot call-count seam and source inspection.
- No registry notification subscription was added; tray refresh remains timer-driven.
- Provider refresh/polling remains the main future performance area if a controlled measurement shows it is material.
- The external installer/scripts still write to the production pipe through their existing `cmd /c echo ...` path; the MenuHost server now enforces the current-user ACL and command validation without changing those out-of-scope callers.
