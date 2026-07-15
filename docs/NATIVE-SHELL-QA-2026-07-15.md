# Native Shell QA - 2026-07-15

## Environment

- Laptop display only: 1920x1200 physical, 150% scaling, 1280x800 logical.
- External LG display was disconnected and is not signed off by this run.
- Production processes: Explorer, one MenuBar, one MenuHost.
- Seelen, YASB, and the polling hot-corner helper were absent.

## Passed

- Preflight: PowerShell parsing, official Windhawk 1.7 SHA-256, 13 native pins.
- Build: MenuBar and MenuHost, Release, zero warnings and zero errors.
- Maximized desktop screenshot after removing the false-fullscreen hide heuristic.
- Restored and maximized Snipping Tool at 150% scaling.
- Apple, Control Center, live Wi-Fi list, Bluetooth, and Notification Center visuals.
- Control Center Wi-Fi/Bluetooth state settles within one second.
- Core Audio changes, reads back, and restores the original volume.
- Six alternating Alt+Tab cycles; no application or shell process closed.
- Apple panel closes immediately when Alt+Tab changes the foreground window.
- Show Desktop twice restores windows.
- Mixed `Win+D` then MenuHost/corner route restores windows without flag drift.
- File Explorer opened, navigated into `qa`, navigated back, and Alt+Tabbed away
  without closing or hanging.
- Maximized content stops above the opaque native dock.
- Notification bell route opens the independent Windows notification/calendar panel.
- Follow-up on 2026-07-16: Windows Search and Weather/Widgets are absent from the
  live dock; both Windows Search visibility registry locations are now asserted.
- Follow-up on 2026-07-16: Show Desktop changes the app label to Finder, and the
  second invocation restores the prior window set.
- 30 second idle sample: MenuBar 56.1 MB stable, 0.286% total-machine CPU;
  MenuHost 52.8 MB stable, 0% sampled CPU.

## Found And Fixed

- Elevated HKCU writes were rejected: split user and privileged promotion phases.
- Successful privileged script was falsely marked failed by an unset `$LASTEXITCODE`:
  removed the invalid wrapper check.
- Maximized Codex was misclassified as fullscreen and hid the bar: removed bar hiding.
- Panels retained the old Seelen offset: moved them to 6 physical pixels below the bar.
- Control Center waited on brightness before updating Wi-Fi/Bluetooth: probes decoupled.
- Bluetooth status launched PowerShell: replaced with the faster `sc.exe` query.
- Show Desktop state drifted after `Win+D`: now derives from visible windows.
- Audio self-test only wrote the same value: now verifies a real change and restore.

## Pending Physical Gates

- Reboot/sign-in persistence check after the final dock update.
- Mixed-DPI visual and behavioral signoff with the external LG display connected.
- Confirm the physical top-bar hit targets (Apple, network, Bluetooth, volume,
  settings, bell, and both Show Desktop corners). The menu bar intentionally uses
  a tool-window surface that the automation API cannot target directly; the same
  handlers and protocols passed their non-pointer routes.
- Confirm the Task View composition by eye. `Win+Tab` did not close or hang any
  process, but desktop capture returned compositor-black fragments while Task View
  was active, so that visual state is not signed off from screenshots alone.
