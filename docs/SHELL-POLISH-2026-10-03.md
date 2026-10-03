# Native shell polish QA — 2026-10-03

## Changes

- Dock: added capture-aware click and drag handling, DPI-aware drag thresholds, cancellation and order restoration, and a bounded hover settle animation. Reduced bevel contrast.
- MenuBar: moved tray icon extraction to a bounded asynchronous cache with stale-result rejection, retry backoff, and last-good icon retention. Added overflow icons, stable tray and telemetry spacing, and two measured clock widths.
- MenuHost: aligned the palette with the neutral shell styling and added a right-aligned live slider percentage.
- Bumped the five native component versions from 1.1.1 to 1.1.2.

## Staged verification

Release candidate built with `scripts/Build-NativeShell.ps1 -Configuration Release -Destination 'qa/polish-20261003/candidate'`.

`scripts/Test-NativeShellRegression.ps1 -SkipBuild -DeploymentRoot 'qa/polish-20261003/candidate' -OutputDirectory 'qa/polish-20261003/worker-regression'` passed all six checks: Dock, mixed-DPI MenuBar, MenuHost Alt+Tab matrix, Supervisor, Awake schedule, and performance sampler.

MenuBar offscreen render QA passed seven cases: 800px and 1280px layouts at 100%, 150%, and 200% scaling, plus a 32-app overflow case at 1280px/200%. The render manifest is under the ignored `qa/polish-20261003/menubar-render-final` directory.

The MenuBar async-cache self-test initially exposed a fixture race when the test inspected a bitmap while its disposal worker was running. The disposal check now waits through the transient `GetPixel` busy state; the focused self-test and subsequent full staged regression passed.

## Acceptance status

Candidate acceptance is complete. The parent full staged regression suite passed all six checks (`qa/polish-20261003/parent-regression/20261003-024645-native-shell-regression.json`), and staged preflight passed with download and live-audio checks skipped.

Controlled deployment completed at 02:47. All five processes and staged file hashes were verified; the existing dock-pins file SHA256 remained `C906043C488129D064BBE7E5C0AC8CB44673EBAC444A733995BF8C65E2A696A2`. The deployment backup is under `%LOCALAPPDATA%/MacMakeover/backups/release-v1.1.2-20261003-024724`. The live profile passed, and `MenuHost --alt-tab-regression-test` returned 0 at 02:49:28.

The parent reviewed physical 1920×1200 at 150% captures (`after-restored.png`, `after-maximized.png`, `after-control.png`, `after-network.png`, `after-bluetooth.png`, and `after-apple.png`): work-area spacing was correct and each menu surface was clean. All 25 live Dock icons exported successfully, including Microsoft Outlook. Private captures remain ignored.

Offscreen fixtures cover synthetic 150% and 200% scaling. An external display was disconnected, so physical mixed-monitor DPI remains unverified. Live audio adjustment and physical Dock pointer gestures were not exercised; pointer gesture semantics passed the regression fixtures. The final commit-stamped rebuild and deployment, push, and GitHub publication are parent release steps.
