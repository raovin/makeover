# Migration Checklist

## Prepare

- Clone this repository on the new Windows machine.
- Open a normal, non-administrator PowerShell session in the repository.
- Allow local scripts for the session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

- Install the current prerequisites. Remote tools remain optional:

```powershell
.\scripts\install-apps.ps1
.\scripts\install-apps.ps1 -IncludeRemoteTools
```

Seelen is intentionally not installed by default. Its retired profile is under
`archive/seelen-ui/` and can be installed only with `-IncludeArchivedSeelen`.

## Restore Production

```powershell
.\scripts\Promote-NativeShell.ps1
```

Approve the single UAC prompt. The promoter builds and deploys MenuBar/MenuHost,
installs the pinned Windhawk style, applies the wallpaper and startup entries,
restarts Explorer, and runs live acceptance.

## Manual Accounts

- Sign into Tailscale or RustDesk only when those tools are required.
- Do not store remote-control credentials or work-account tokens in this repo.

## Verify

```powershell
.\scripts\Test-NativeShellPreflight.ps1 -SkipDownloadCheck
.\scripts\Test-NativeShellProfile.ps1
```

Confirm restored and maximized windows stop between the top bar and dock, native
Alt+Tab works, every top-bar control opens its own surface, and the dock remains
visible with complete icons. Repeat mixed-DPI QA when the external display is
physically connected.
