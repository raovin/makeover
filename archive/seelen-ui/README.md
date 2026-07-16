# Seelen UI Archive

This directory preserves the final Seelen-based makeover generation for reference
or an intentional future rollback. It is not part of the production profile.

## Contents

- `config/`: last committed Seelen settings, toolbar, WEG dock, theme, and plugin.
- `scripts/`: legacy backup/restore, verifier, pin migration, and rollback scripts.
- `docs/`: historical handovers, design prompts, audit evidence, risks, and QA.

## Safety

- Do not run these scripts while evaluating the native production shell.
- Seelen shortcuts remain disabled in the archived profile because they previously
  interfered with native Alt+Tab and lock-screen input.
- The archived restore can disable the native Windhawk dock profile and re-enable
  the existing Seelen scheduled task. It assumes Seelen is still installed.
- Review the historical documents as dated evidence, not current instructions.

The archived `verify.ps1` checks the retired Seelen generation only. Production
verification remains `scripts/verify.ps1` at the repository root.

## Optional Rollback

From a normal PowerShell session at the repository root:

```powershell
.\archive\seelen-ui\scripts\Restore-SeelenProfile.ps1
```

To install Seelen on a future machine before experimenting:

```powershell
.\scripts\install-apps.ps1 -IncludeArchivedSeelen
```

Return to production with:

```powershell
.\scripts\Promote-NativeShell.ps1
```
