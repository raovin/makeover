# System Reliability Audit - 2026-07-22

## Scope

This audit followed a complete Wi-Fi outage that required a reboot, a slow native
shell startup, an Explorer RPC error, and repeated reports of 12-13 GB physical
memory use on a 16 GB system.

## Network Incident

The outage was an Intel AX211 driver/firmware-path failure, not a Mac Makeover
network change.

- The System log contained 396 `Netwtw16` event 6062 warnings in the preceding
  30 days, including 37 in the final 24 hours.
- At 11:54 on 22 July, event 5010 recorded that the AX211 returned an invalid
  value to the driver.
- WLAN AutoConfig recorded wireless security stopping and restarting at 13:22
  and 13:28, immediately alongside the Intel warnings. At 13:32 security stopped
  and did not recover until the reboot.
- The installed driver was `23.140.0.3` from February 2025. Intel's current
  package is `24.50.0`, which installs AX211 driver `24.50.0.4`.
- Tailscale was running but did not own the default route. The disconnected
  Surfshark adapter had no usable route. Neither explains the WLAN security
  resets.

## Remediation

- Exported `oem272.inf` and its payload to:
  `C:\Users\VineethRao\AppData\Local\MacMakeover\reliability\driver-backup-20260722`
- Downloaded Intel package `WiFi-24.50.0-Driver64-Win10-Win11.exe` directly from
  Intel, verified the published SHA-256
  `17EFCFEDB6075FDDB731022D67263888A9AFF04C9134CC0F1A198F8751CE1761`, and
  verified its Intel Authenticode signature.
- Installed AX211 driver `24.50.0.4`; the adapter reconnected without a reboot.
- Changed wireless power saving from Medium Power Saving to Maximum Performance
  on battery. AC was already Maximum Performance.
- Added `scripts/Set-WifiReliability.ps1` as an auditable, rollback-recording
  helper for staging a 5 GHz preference. The preference was not applied during
  this pass because its UAC request was not approved; the adapter remains on its
  stable existing BSSID. The visible 5 GHz BSSID uses DFS channel 108, so forcing
  it without a controlled test would not be a reliability improvement.
- No always-running network watchdog was added. The repaired driver and Windows
  event logs provide a simpler failure boundary without another startup process
  capable of resetting the adapter during a meeting.
- Added `scripts/Test-SystemReliability.ps1`, a read-only acceptance command that
  repeats driver, route, gateway, public-IP, DNS, recent Intel-event, memory,
  firmware, remote-access, native-shell, and archived-pin checks on demand.

The first traffic soak passed 121/121 gateway probes, 120/121 public probes, and
60/60 DNS lookups. The one missed public ICMP reply did not coincide with a
gateway or DNS failure. A final three-minute soak passed 181/181 gateway probes,
181/181 public probes, and 90/90 DNS lookups. Early 6062 notices during driver
replacement did not restart WLAN security; no further 6062 event occurred after
14:36 during the Windows repair downloads or final soak.

## Windows Integrity And Startup

- Windows Update reported no pending OS or driver update. The only offered item
  was a Defender intelligence definition.
- A Perflib error reported a missing SysMain counter DLL registration. The DLL
  itself was present, but the expected performance registration was absent.
- `scripts/Repair-WindowsReliability.ps1` runs the supported DISM, SFC, `lodctr`,
  and WMI resynchronization sequence and writes a transcript under
  `C:\ProgramData\MacMakeover\logs`.
- DISM found missing protected Windows resource payloads, acquired repair content
  from Microsoft Update, and completed successfully without requiring a reboot.
- SFC found corrupt protected files and repaired them successfully. `lodctr /R`
  then rebuilt performance-counter registrations and WMI resynchronization
  completed. The transcript is
  `C:\ProgramData\MacMakeover\logs\system-reliability-repair-20260722-142234.log`.
- The retired Seelen scheduled task is disabled and no Seelen process runs.
  Windhawk UI startup remains disabled, the Windhawk service is not active, and
  the native bar, host, and dock each have exactly one process.
- The prior Explorer RPC popup followed an Explorer access violation in
  `twinui.pcshell.dll`. It occurred while the retired Seelen service was starting,
  before the native binaries launched. Disabling that stale task removed the
  conflicting shell startup path.

## Firmware

This exact system is an HP EliteBook 8 G1i 14 with board ID `8D89` and X70 BIOS
`01.02.04` from August 2025. HP publishes critical X70 firmware `01.04.03` for
board ID `8D89`; its notes include system-stability improvements.

The matching HP package was staged at:
`C:\Users\VineethRao\AppData\Local\MacMakeover\reliability\sp172966-HP-BIOS-X70-01.04.03.exe`

Its HP-published and locally verified SHA-256 is
`0F8EECD345193EE74AE0BBA0B6E49B32C0A790338F9AB06BCD96FEE9AAE6CF2C`, and its
Authenticode signature is valid. Firmware installation requires a controlled
restart and should only be started while the laptop is connected to AC power.

## Memory Findings

The observed 12.25 GB physical use was high but accounted for. At the audit
snapshot, 3.18 GB remained available and commit was 21.02/32.33 GB.

| Process family | Working set | Private commit | Notes |
| --- | ---: | ---: | --- |
| Codex/ChatGPT and automation runtimes | about 3.0 GB | over 5 GB | Active task, browser and computer-use runtimes |
| Chrome | 1.0 GB | 1.38 GB | 18 processes |
| Edge and WebView2 apps | 1.49 GB | 3.12 GB | Teams, TeamViewer, Search, M365 and Edge |
| Defender and enterprise sensors | about 0.7 GB | about 1.1 GB | `MsMpEng`, `MsSense` and related services |
| Memory compression | 0.82 GB | negligible | Windows response to physical pressure |
| Native Mac Makeover shell | about 0.06 GB current | about 0.05 GB current | Bar, dock and menu host combined; earlier audit snapshot was about 0.15 GB during repair activity |

This is application pressure, not a native-shell leak. The audit itself briefly
increased usage through DISM/TiWorker and the Computer Use runtime; the latter was
reset after inspection. TeamViewer was an unnecessary auto-starting WebView
application even though RustDesk is installed. Winget incorrectly reported an
earlier successful uninstall while the vendor service and files remained. The
vendor uninstaller was subsequently approved and completed with exit code 0;
TeamViewer's process, service, package registration, and Winget entry are absent.
RustDesk remains installed and its service is running. Two inert historical log
files, about 10 MB combined, remain under `C:\Program Files\TeamViewer`; no
TeamViewer executable or startup path remains.

## Live Visual And Interaction Acceptance

Fresh physical desktop captures were taken after the secure desktop was cleared.

- Both the 1920x1200 150%-scaled laptop panel and 1920x1080 external display show
  one menu bar and one centered dock with continuous wallpaper behind them.
- Maximized Chrome respected the reserved top and bottom work areas. The bar and
  dock remained visible, with no window content hidden behind either surface.
- A real `Alt+Tab` from maximized Chrome switched immediately to Codex; the active
  application label updated on both bars and no app or shell process stopped.
- Apple, Wi-Fi, Bluetooth, Control Center, and Notification Center were opened
  through their production protocol paths and captured. Each rendered its own
  surface at the correct edge with no clipping, overlap, duplicate panel, terminal
  window, or unresponsive host.
- The panel captures are in `qa/system-reliability-panel-*-20260722.png`; the
  full, per-display, maximized, and Alt+Tab captures use the corresponding
  `qa/system-reliability-*-20260722.png` names.

## Acceptance Boundary

Do not close this incident until all of the following pass:

- Intel driver remains `24.50.0.4` after restart.
- Gateway, public IP, and DNS traffic pass a sustained soak.
- No new WLAN security stop/restart loop or event 5010 appears.
- DISM/SFC and performance-counter repair complete successfully. **Passed.**
- TeamViewer is absent and RustDesk remains installed/running. **Passed.**
- Seelen and Windhawk remain inactive; one native bar, dock, and menu host run.
- Native preflight, live profile, taskbar pins, Alt+Tab, maximized/restored work
  areas, wallpaper, and screenshot QA pass. **Passed.**
- BIOS `01.04.03` is installed at a controlled reboot, then the network soak is
  repeated. **Pending a user-approved restart window.**
