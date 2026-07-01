# Migration checklist

## Before restoring

- Clone this repo on the new Windows machine.
- Confirm PowerShell can run local scripts:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

- Install the core desktop apps (Seelen UI). Add `-IncludeRemoteTools` to also install RustDesk and Tailscale:

```powershell
.\scripts\install-apps.ps1
.\scripts\install-apps.ps1 -IncludeRemoteTools
```

## Restore

- Run the normal restore:

```powershell
.\scripts\restore.ps1
```

- Optional appearance extras:

```powershell
.\scripts\restore.ps1 -ApplyWallpaper -ApplyCursors
```

## Manual setup

- Sign into Tailscale.
- Sign into RustDesk or configure the new device in RustDesk.
- Grant remote-control permissions where required.
- Confirm Seelen autostarts at login.

## Verify

```powershell
.\scripts\verify.ps1 -CaptureScreenshot
```

Check:

- Top menu bar is visible.
- Apple-style mark appears on the left.
- Focused app name does not overlap.
- CPU/memory/network telemetry is centered.
- The right-side Wi-Fi/battery/Control Center strip, notification bell, and date/time are legible and distinct.
- Dock is visible at the bottom.
- Native Windows Alt+Tab works normally.
- Lock screen PIN entry works normally.
