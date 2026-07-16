# Claude Design Prompt: mac-makeover Visual Redesign Pass

Paste this into Claude Design / Claude Code when outsourcing the next design pass.

```text
You are taking over the visual design and adversarial QA pass for a Windows 11 macOS-style desktop makeover.

Repo to use as the single source of truth:
C:\Users\VineethRao\source\repos\mac-makeover

Do not work from memory and do not edit the old frozen backup under:
C:\Users\VineethRao\source\repos\brunel\workspace\desktop\mac-makeover

Start by reading these files in the repo:
- README.md
- CLAUDE.md
- docs\CODEX-HANDOVER.md
- config\seelen\data\seelen-fancy-toolbar\state.yml
- config\seelen\themes\macos-glass\styles\fancy-toolbar.css
- config\seelen\themes\macos-glass\styles\weg.css
- config\hot-corners.json
- scripts\start-hot-corners.ps1
- scripts\verify.ps1
- tools\MacMakeover.MenuHost\Program.cs

Also inspect recent history:
git log --oneline -8
git status --short

User goal:
Make this setup feel less like a themed Windows shell and more like a polished Mac-inspired desktop. The focus is visual quality and interaction polish for:
- the top menu bar
- the Apple menu
- the right-side status strip / Control Center
- the bottom dock
- show-desktop corner behavior
- native Alt+Tab and lock-screen safety

Current intended behavior:
- Top-left Apple mark opens a compact Apple menu quickly.
- Clicking the Apple mark must not open a terminal window.
- The top-right sliders control opens the custom MenuHost Control Center, not Seelen's old quick-settings or power-options flyout.
- Wi-Fi, Bluetooth, sliders, bell, and date/time are separate click targets, so their visual affordances should read as distinct controls.
- Wi-Fi opens the custom MenuHost Network panel and is visually skinned as a Wi-Fi glyph; Bluetooth opens the custom MenuHost Bluetooth panel; the bell opens Seelen notifications; date/time opens the calendar popup.
- Battery is a right-side Mac-style system readout merged with charging state, not a separate power button.
- Wi-Fi/network belongs in the MacBook-style right-side status area.
- Battery and charging should be presented as one combined status item, not two unrelated icons.
- Throughput/readout clutter should not live in the top bar unless the design makes it genuinely elegant.
- Top-left and top-right physical corner click zones should still Show Desktop.
- Alt+Tab must remain native Windows Alt+Tab.
- Lock-screen PIN input must remain safe.

Critical guardrails:
- Do not re-enable Seelen shortcuts or Seelen task switcher behavior.
- Do not re-add @seelen/tb-quick-settings unless the user explicitly asks for the old Seelen flyout.
- Keep the Apple toolbar item wired directly to `macmakeover-apple-menu:`. The handler is now a fast MenuHost pipe echo; broad helper pixel zones are disabled because they can fire while clicking app chrome.
- The sliders item should wire directly to macmakeover-control-center:, whose protocol writes to the resident tools\MacMakeover.MenuHost named pipe and has a self-healing --show fallback.
- The macmakeover-* URI handlers are fallback/restore plumbing only.
- Do not reintroduce visible PowerShell, Windows Terminal, or old power-options screens.
- Stop Seelen before editing Seelen config/theme files.
- Do not force-restart explorer.exe while Seelen is running.
- Do not disable or bypass Windows Security.
- Do not touch RustDesk, Tailscale, TeamViewer, browser sessions, or work-account state unless explicitly asked.
- Keep the repo as the only lasting source of truth. Commit useful lasting changes.

Design assignment:
1. Do a visual audit first. Capture screenshots before changing anything.
2. Identify the highest-impact polish problems, especially overlap, clipping, lag, fake affordances, hover/active state weirdness, dock transparency inconsistency, and menu/control-center ugliness.
3. Implement one focused design pass that improves real files in this repo. Favor restrained, Mac-like polish over novelty.
4. Keep changes small enough that they can be reviewed and reverted if needed.
5. Avoid a mockup-only answer. The result should be implemented in repo files and verified live.

Design direction:
- Top bar should feel like a real menu bar: calm, aligned, compact, readable.
- The right-side system controls should feel MacBook-like but must not pretend to be one shared button.
- Use subtle individual hover/active states because the icons now open different panels.
- Apple menu and Control Center should feel immediate, clean, and intentional.
- Dock glass should be stable and readable, with useful contrast and active indicators.
- Avoid one-note palettes and avoid overusing blur/glow until text becomes fuzzy.
- No clipped text, no accidental separator lines, no ghost tooltips, no overlapping app names or icons.

Verification requirements before saying done:
- Run:
  .\scripts\verify.ps1 -CaptureScreenshot
- Inspect the saved full screenshot plus the top and bottom crops under qa\.
- Test real interactions, not just static screenshots:
  - Apple mark opens the Apple menu quickly and without a terminal.
  - Wi-Fi opens the custom MenuHost Network panel and stays visually Wi-Fi even when a VPN/tunnel route is active.
  - Bluetooth opens the custom MenuHost Bluetooth panel.
  - Battery appears in the right Mac-style system cluster, while the center cluster stays CPU/RAM/NET only.
  - Sliders open the custom Control Center.
  - The bell opens Notification Center instead of Control Center.
  - Date/time opens the calendar popup and does not leave Control Center underneath it.
  - The top-right Control Center does not show Seelen's old power/options flyout.
  - Top-left and top-right physical corner clicks still Show Desktop.
  - Alt+Tab is still native Windows Alt+Tab.
  - The dock remains visible, stable, and not randomly transparent.
- Run:
  git diff --check
- If PowerShell scripts are touched, parser-check them.
- If tools\MacMakeover.MenuHost is touched, run a dotnet build for that project.

Local QA reference images may exist under qa\. Treat them as private local references only. Do not publish or upload them elsewhere.

Expected final response:
- Brief audit findings.
- Files changed.
- Exact verification commands run.
- Screenshot paths inspected.
- Any remaining risks or tradeoffs.
- Git commit hash if you committed changes.

Do not claim the task is done unless the live visual and interaction QA above has actually been performed.
```
