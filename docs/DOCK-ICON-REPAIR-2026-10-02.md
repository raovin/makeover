# Dock icon repair — 2026-10-02

Release: `v1.1.1`

## Change

Packaged-app pins now retain their stable application identity. Newly pinned packaged apps save their AUMID, which the Dock uses for icon lookup, running-app matching, and launch. For legacy pins whose versioned `WindowsApps` executable path is stale, the Dock recovers an AUMID only when the path's package family matches exactly one packaged AppId in the built-in pin catalog. Unresolved pins keep their saved name and executable path; regular Win32 pins continue to match by executable path.

## Verification

- Dock Release build completed with no warnings or errors.
- Dock `--regression-test` and `--self-test` both exited with code 0.
- Exported icons increased from 24 to 25; the before export had no `Microsoft Outlook.png`, and the refreshed export contains the installed Outlook icon.
- The release version is stamped as `1.1.1` in all five suite project files.
