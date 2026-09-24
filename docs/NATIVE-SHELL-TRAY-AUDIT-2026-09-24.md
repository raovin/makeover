# Native shell tray audit — 2026-09-24

## Result

MenuBar tray rows now represent live notification registrations instead of
process-name guesses. Left-click still activates the owning process. Right-click
dispatches the owning native menu when a supported native owner is available.
The Tailscale path uses its real hidden `WalkNotifyIconSink` and callback message;
it does not recreate or mirror Tailscale's menu.

## Confirmed and fixed

- Tailscale's `InitialTooltip` registry value was empty, so the previous capture
  discarded the running icon. Display-name resolution now falls back to version
  metadata and known executable names.
- Capture previously grouped registrations by executable path. It now validates
  the process path, validates GUID registrations with
  `Shell_NotifyIconGetRect`, preserves distinct live GUIDs, deduplicates repeated
  GUID rows, and keeps at most one conservative legacy row per executable when
  no GUID is available.
- MenuBar previously ignored right-button input. It now passes the caller's
  screen point to native dispatch.
- The rendered notification token now includes icon snapshot and GUID identity,
  so a tray artwork/identity change invalidates the paint cache.
- Provider refresh shutdown now serializes timer startup with disposal, rejects
  late results, and retains the cancellation source until cancellation and all
  registered workers finish. Reader cancellation runs off the UI thread while
  work is active, and callback exceptions cannot escape that worker.
- Existing changes disabling background Gemini sign-in polling and making the
  wallpaper guard headless were reviewed and retained. Wallpaper preflight and
  profile checks now validate the executable, flags, and quoted script path.
- The `.gitignore` now excludes only the requested local agent metadata and
  generated Awake publish directory; existing untracked contents were not
  removed.

## Native dispatch contract

Tailscale's Windows client uses the Tailscale Walk toolkit. The adapter requires
all of the following before posting a callback:

1. the registry GUID is live according to `Shell_NotifyIconGetRect`;
2. the executable is the known `tailscale-ipn.exe` client;
3. exactly one live top-level `WalkNotifyIconSink` belongs to that executable;
4. the menu anchor is the actual MenuBar right-click screen point.

The callback is posted asynchronously, so a hung tray client cannot block the
MenuBar UI thread. If the owner is missing, ambiguous, or no longer live, the
operation fails closed and logs a diagnostic. Awake & Available continues to use
its existing single-instance menu signal. Other legacy/no-GUID registrations are
shown only conservatively and do not receive a fabricated context menu.

The shell API's GUID identity and rectangle behavior are documented by Microsoft:
[NOTIFYICONIDENTIFIER](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ns-shellapi-notifyiconidentifier)
and [Shell_NotifyIconGetRect](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyicongetrect).
The Walk callback contract is based on the client source at
[tailscale/walk notifyicon.go](https://github.com/tailscale/walk/blob/main/notifyicon.go).

## Live evidence

On the active desktop, Tailscale was running as `tailscale-ipn.exe` with an empty
tooltip, GUID `{FBED1924-0F0E-4AE6-87D3-246DCD41EEE1}`, and one
`WalkNotifyIconSink` window. A narrowly scoped probe posted `WM_USER + 3` with
`WM_CONTEXTMENU` at the caller point and observed:

```text
Posted=true, Sink=0x2030E, TargetPid=6844
MenuOpened=true, MenuPid=6844, MenuOwnerMatched=true
NativeMenuRemaining=false
```

No menu item was selected and no VPN state was changed.

The custom Dock currently hides Explorer's notification area. A valid shell icon
rectangle therefore cannot safely justify synthetic pointer input: it may be
stale or refer to the hidden taskbar. Generic shell mouse synthesis is
intentionally not used. To support arbitrary third-party native menus under a
hidden taskbar, the minimal future architecture is either to keep the Explorer
notification area interactable or to add an explicit app-owned native dispatch
adapter per client contract.

## Verification

- `dotnet restore tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj` — passed.
- `dotnet build tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --no-restore` — passed, 0 warnings, 0 errors.
- `dotnet run --project tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --no-build -- --snapshot-tray <temp-file>` — passed; the live snapshot included Tailscale with its GUID.
- `dotnet run --project tools/MacMakeover.MenuBar/MacMakeover.MenuBar.csproj --no-build -- --self-test` — passed, including the tray/provider and coordinator lifecycle regressions.
- `git diff --check` — passed.

- Final integrated Release build and MenuBar `--self-test` — passed after the
  cancellation correction, with 0 build warnings or errors.
- MenuHost, Dock, and Supervisor builds — passed; Dock regression test passed.
- PowerShell parsing and valid/invalid wallpaper action checks — passed.
- `Test-NativeShellPreflight.ps1 -SkipDownloadCheck` — passed on the active
  desktop (one display, 16 pinned shortcuts).
- `Test-NativeShellProfile.ps1` — failed because the installed/running MenuBar
  executable hash differs from the existing deployment manifest. This is an
  installation-state mismatch; source changes have not been promoted.

Luna Max implemented and audited tray behavior; Grok CLI implemented the
wallpaper validation and coordinator corrections; AGY CLI independently reviewed
the supplied source. Review and verification completed on 2026-09-25.

MenuHost and Supervisor were audited; no additional source change was justified.
No production install, restart, registry mutation, or VPN operation was performed.
The updated shell still requires promotion through the documented interactive
installation workflow before these fixes affect the running MenuBar.
