# Dock icon crash audit — 2026-09-28

## Status

The focused fix was implemented through the existing Luna Max task, reviewed in the parent checkout, and deployed on 2026-09-28. Grok CLI and AGY CLI also reviewed the failure path.

## Evidence and findings

The reported production path was:

`DockForm.ApplyDockState` → `DockItem` construction → `RunningApp.LoadIcon` → `Icon.BmpFrame`, with `System.ArgumentException: Parameter is not valid`.

The running-app path decoded the first non-zero HICON returned by a foreign window synchronously. A stale or malformed handle could therefore escape through the UI callback. The conversion also created an intermediate `Bitmap` without disposing it. The analogous `PinnedApp.LoadFileIcon` path had the same intermediate-bitmap leak; its `SHGetFileInfo` HICON is caller-owned and must be released on every conversion outcome.

## Changes

- Added a shared HICON conversion helper that:
  - duplicates borrowed window HICONs with `CopyIcon` before decoding;
  - destroys only the duplicate it owns, or the explicitly owned `SHGetFileInfo` handle;
  - disposes the intermediate `Icon` and `Bitmap` objects;
  - contains expected `ArgumentException`, `ExternalException`, `InvalidOperationException`, and `OutOfMemoryException` conversion failures.
- Changed `RunningApp.LoadIcon` to continue through file, `WM_GETICON` big/small, class-icon, and later-window candidates instead of returning from the first bad handle.
- Replaced synchronous foreign-window icon messages with `SendMessageTimeoutW` using `SMTO_BLOCK | SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT`: each message is capped at 100 ms and the window-candidate lookup has a 250 ms per-app budget.
- Wrapped icon loading at `DockItem` construction for the expected icon failures only. An app entry remains present and uses the existing initials tile when no icon can be decoded; `ApplyDockState` was not given a broad exception catch.
- Routed `PinnedApp.LoadFileIcon` through the same ownership-safe helper.

## Verification

The Release build completed with zero warnings and zero errors:

`dotnet build tools/MacMakeover.Dock/MacMakeover.Dock.csproj --configuration Release`

Both supported executable checks returned exit code 0:

- `MacMakeover.Dock.exe --regression-test`
- `MacMakeover.Dock.exe --self-test`

The regression suite now includes focused coverage for:

- a real valid native icon handle still decoding;
- rejection of a destroyed HICON, and separately recovery from an invalid window handle to a valid later window candidate;
- a running item with no usable icon retaining its identity and rendering initials;
- borrowed-handle survival after conversion;
- destruction of an owned handle after a controlled decoder `ArgumentException`;
- a QA window that stalls `WM_GETICON` for two seconds, confirming the lookup returns in less than one second.

The parent independently reviewed the incremental source diff, reran the Release build (zero warnings/errors), regression suite and self-test (both exit 0), and checked whitespace. No QA probe processes remained. Grok's suggestion that all handle-backed icons fail on .NET 10 was rejected after checking the [runtime source](https://github.com/dotnet/winforms/blob/v10.0.9/src/System.Drawing.Common/src/System/Drawing/Icon.cs); the real valid-handle regression also passed.

## Deployment verification

The four published Dock artifacts were copied to the existing deployment and individually verified with SHA256. Dock and Supervisor were restarted through the existing task setup; Explorer was not restarted. The previous artifacts and deployment manifest are backed up at `%LOCALAPPDATA%\MacMakeover\backups\dock-icon-crash-20260928-092836`.

The deployed self-test returned 0. `scripts/Test-NativeShellProfile.ps1` passed, and Dock PID 26772 and Supervisor PID 25192 remained responsive after startup. The profile output is retained in `qa/dock-icon-crash-profile-20260928.log`.

## Limits

This verifies the managed fallback, ownership, disposal, and timeout behavior with real Windows icon handles and QA windows. It does not reproduce the exact third-party production HICON, identify the supplying app, prove every vendor-specific icon implementation, or replace an extended production UI soak. The 250 ms budget applies to foreign-window icon lookups; file/shell icon extraction remains synchronous and is not covered by that deadline.
