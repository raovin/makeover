# Mac Makeover Risk Register

Reviewed: 2026-07-10. Ratings are qualitative: Low, Medium, High.

| ID | Fragile area | Impact | Likelihood | Mitigation | Verification method | Current state |
|---|---|---:|---:|---|---|---|
| R-01 | MenuHost always anchors to primary monitor | High | High on multi-monitor systems | Select/capture target screen from initiating pointer before handle creation | Open from each monitor; inspect log device and screenshot | Mitigated: DISPLAY2 pointer+pipe proof passed; actual toolbar recheck open |
| R-02 | Virtual-desktop top/bottom crops describe different monitors | High | High with stacked/offset displays | DPI-aware per-monitor full/top/bottom crops; retain full virtual capture | Compare dimensions/rectangles/hashes to `Screen.AllScreens` | Resolved and verifier-tested on two monitors |
| R-03 | Seelen shortcuts/task switcher intercept Alt+Tab or lock input | Critical | Low with guards | Force disabled JSON; verifier gate; never enable task switcher | Static JSON/settings check; native Alt+Tab; user-observed lock test | Static PASS; Alt+Tab PASS in Apple path |
| R-04 | Topmost MenuHost popup lingers over Alt+Tab | High | Medium | Keep MenuHost out of the topmost band; no-activate `HWND_TOP`; retain Alt/foreground timer | Apple/Control open then Alt+Tab and inspect host log | Resolved: Apple and Control both dismiss during native switching |
| R-05 | Bell/date stack with MenuHost or fail to open Windows surface | High | Medium | Explicitly close MenuHost before native notification action; keep separate test cases | Open custom panel, then bell/date, inspect full screen | OPEN; protocol screenshot did not prove surface |
| R-06 | Seelen performance mode hides bars on battery | High | Medium if config drifts | Keep all performance modes Disabled; verifier failure | JSON parse and AC/battery-safe observation | Static PASS; power-state switch not performed |
| R-07 | YAML/schema edit blanks toolbar | High | Medium | Stop Seelen before edit; parser/schema-aware diff; log check after restart | Seelen `SerdeYaml`/panic scan and screenshot | PASS after redesign: both toolbar and WEG instances returned `Ready` |
| R-08 | Dock covers maximized content | High | Medium | Seelen WEG sole ownership; no MenuHost appbar; per-monitor work-area checks | Compare client/window bounds with monitor work area; screenshots | PASS after compact-dock redesign and direct Explorer maximize/restore |
| R-09 | Dock becomes translucent | Medium | Medium | Opaque theme colors and verifier guard | bottom crop on each monitor | Baseline PASS |
| R-10 | Blocking `netsh`/PowerShell freezes MenuHost UI | High | Medium | Async probes, cancellation, real timeout, stale-data placeholder | Simulate slow command; ensure Apple/Control remain responsive | Warm latency PASS; failure path untested |
| R-11 | Bluetooth service status misreports radio state | Medium | Medium | Query radio/device state rather than only `bthserv` | Toggle radio manually and compare panel | OPEN |
| R-12 | Repeated panels leak handles/memory | High | High for Control Center churn | Cancel per-form enrichment; enforce timeout before output consumption; kill only timed-out child tree; idempotent disposal | Repeated warm Control batches; child-process inventory after settle | Mitigated: pre-fix +89 handles with live child; final warm batch +4 handles with no child probes |
| R-13 | Duplicate MenuHost processes cause flicker | High | Low | Named mutex; verify one PID before/after churn | process count and PID comparison | PASS for 10 cycles |
| R-14 | URI handler opens a visible terminal | High | Low with current registry | Headless conhost + resident pipe; verifier rejects wrong command | actual click video/screenshot plus process/window sample | Apple PASS; other actual clicks OPEN |
| R-15 | Broad hidden click zones fire over app chrome | High | Low with current config | Keep all item routing booleans false; remove dormant code later | verifier/config check and near-edge click test | Static PASS; adversarial near-edge OPEN |
| R-16 | Live/repo WEG drift breaks pins after app updates | Medium | High | Prefer UMIDs; refresh versioned paths before restore; add path-aware follow-up | no-index diff; Seelen log scan | Current Outlook/Codex/Claude paths refreshed; no new WEG `NotFound` after 13:59; long-term version drift remains |
| R-17 | Seelen restart does not restore both bars/docks | High | Medium | scheduled-task restart test and two-monitor screenshot | stop/start Seelen, wait Ready, run verifier | PASS in this audit on both monitors |
| R-18 | QA automation cannot activate no-activate shell surfaces | Medium | Medium | Treat protocol/static tests as partial only; require user-observed click pass when automation blocks | explicit result labels in matrix | Encountered during baseline |
| R-19 | Documentation contradicts live ownership model | Medium | High | consolidate handover after runtime stabilization | source-to-doc review | Observed |
| R-20 | Lock-screen test itself disrupts access | Critical | Low | never automate credentials; keep shortcut static guards; user performs final lock/unlock observation | user confirmation of normal PIN input | Not executed automatically |
| R-21 | Any click on a display above/left of primary is classified as PrimaryScreen top-left | Critical | High on negative-coordinate layouts | Use `Screen.FromPoint`; reject points outside selected monitor bounds; verifier forbids `PrimaryScreen.Bounds` in the helper | Run helper and single/double-click Bruno body on the negative-coordinate display; inspect hot-corner log | Resolved after real-use regression report; direct Bruno retest PASS, no new Show Desktop log entry |

## Risk acceptance

No Critical or High risk is accepted as resolved by a static verifier alone. R-02 and R-17 have direct runtime/visual evidence. R-01 has monitor-placement runtime evidence but still needs the final actual toolbar click. R-03 has strong static protection but still needs a user-observed lock-screen confirmation for full product acceptance. R-04, R-05, R-12, and R-15 remain release gates.
