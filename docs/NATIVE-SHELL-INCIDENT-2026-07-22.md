# Native Shell and Wi-Fi Incident - 2026-07-22

## Reported symptoms

- Internet connectivity stopped while other devices on the same connection remained online.
- A reboot restored connectivity.
- The replacement menu bars and docks took unusually long to appear after login.
- Explorer displayed `The remote procedure call failed and did not execute.`

## Timeline and evidence

- 13:22:12: Intel AX211 wireless security restarted.
- 13:22:14: the `Netwtw16` provider logged warning 6062.
- 13:28:52: wireless security restarted again.
- 13:28:54: `Netwtw16` logged a second warning 6062.
- 13:32:24: Windows rebooted normally at the user's request.
- 13:33:00: the legacy Seelen scheduled task launched `slu-service.exe`.
- 13:33:07: Explorer crashed in `twinui.pcshell.dll` with access violation
  `0xc0000005`.
- 13:33:20: Explorer restarted.
- 13:33:23: Seelen UI and its WebView processes launched.
- 13:34:59-13:36:01: the native Dock, MenuBar, and MenuHost finally launched.

The native shell executables started nearly two minutes after the Explorer crash, so
they could not have caused that crash during this boot. Seelen started before the
crash and competed with the replacement shell afterward. It is a credible shell
conflict, although the Windows crash record alone cannot prove which caller triggered
the fault inside `twinui.pcshell.dll`.

The Wi-Fi loss is separately evidenced by two Intel driver/security resets. The recent
MacMakeover changes altered Dock AppBar rendering and did not modify adapters, routes,
DNS, WLAN profiles, drivers, or network services. MenuHost's Wi-Fi panel uses read-only
`netsh wlan show` queries unless the user explicitly chooses a network.

## Repairs applied

- Stopped Seelen and permanently disabled its scheduled logon task.
- Removed all live Seelen/SLU/WebView processes from the production shell.
- Completed the privileged wallpaper repair and enabled its maintenance task.
- Fixed `Repair-NativeWallpaperPolicy.ps1`: its P/Invoke method was inaccessible to
  PowerShell because it had been declared `internal` instead of `public`.
- Made promotion acceptance retry the short Explorer/native-taskbar startup race.
- Made a passing live-profile test explicitly return exit code zero.

## Acceptance results

- Native-shell preflight passed on both displays.
- Live profile passed with one responsive MenuBar, MenuHost, and Dock.
- Seelen task is disabled and no legacy process remains.
- Explorer restart rehearsal completed and was accepted in 24.1 seconds, including
  fixed waits and the full live-profile verification.
- Visual capture showed both menu bars and docks, no duplicate taskbar, no popup, and
  correct maximized-window work areas.
- Network test: 15/15 gateway probes and 15/15 internet probes succeeded.
- DNS test: 10/10 resolutions succeeded.
- No additional `Netwtw16` warning appeared during the post-repair test window.

## Wi-Fi follow-up

The installed Intel AX211 driver is `23.140.0.3` from February 2025. Intel's current
package is `24.50.0` and installs AX211 driver `24.50.0.4`; Intel's June 2026 release
notes describe Windows quality, stability, and security improvements. Installing a
network driver intentionally interrupts Wi-Fi and should be done only with the user
present and after exporting the current package for rollback.

- Intel package: <https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html>
- Intel release notes: <https://downloadmirror.intel.com/922739/ReleaseNotes_WiFi_24.50.0.pdf>
