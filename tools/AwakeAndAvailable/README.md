# Awake & Available for Windows

A native Windows notification-area app inspired by
[newmarcel/KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake).

It can prevent the PC and display from sleeping and can generate optional mouse activity for Microsoft Teams.

## Native-shell integration

This project is tracked inside mac-makeover because it supplies the always-on notification-area
control used to prevent sleep and optionally keep Teams active. `Build-NativeShell.ps1` publishes it
as a single file, and native-shell promotion installs it to:

```text
%LOCALAPPDATA%\MacMakeover\bin\AwakeAndAvailable.exe
```

Launching that executable while it is already running opens the existing process's tray menu; it
does not create a duplicate process or display an "already running" dialog.

## Standalone run

The standalone build script writes the application to:

```text
dist\win-x64\AwakeAndAvailable.exe
```

Double-click the executable, then use its notification-area icon. Double-clicking the icon toggles sleep prevention.

To rebuild on this computer:

```powershell
.\build.ps1
```

## Teams modes

- **Mouse jiggle (recommended):** moves the pointer by one pixel only after Windows reports that the computer is idle.
- **Click saved safe point:** clicks a captured screen position only while idle. Capture a harmless blank area and recapture it after moving windows or changing displays.

Teams activity is off every time the program starts. Click mode requires confirmation each time it is enabled. These modes are best-effort and cannot override Microsoft or organizational presence policies.

Settings are stored in `%LOCALAPPDATA%\AwakeAndAvailable\settings.json`.

## Icon

The original app icon is stored in `Assets\awake-available.png`. To regenerate the multi-resolution
Windows icon after changing the master image, run `Scripts\create-icon.py` with Python and Pillow.
