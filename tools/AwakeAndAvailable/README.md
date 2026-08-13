# Awake & Available for Windows

A native Windows notification-area app inspired by
[newmarcel/KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake).

It can prevent the PC and display from sleeping and can generate optional mouse activity for Microsoft Teams.

By default, automation follows mainland Portugal time: active from **09:00 inclusive until 18:00
exclusive**, with daylight-saving changes handled by the `Europe/Lisbon` time zone.

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

- **Keyboard + mouse pulse (recommended):** uses Windows `SendInput` to emit an unused F15 key and a one-pixel mouse movement, then verifies that Windows accepted it.
- **Mouse-only pulse:** uses native injected mouse movement without changing the final pointer position.
- **Click saved safe point:** clicks a captured screen position only while idle. Capture a harmless blank area and recapture it after moving windows or changing displays.

The selected non-clicking Teams mode persists across launches and defaults to the combined input pulse. Click mode requires confirmation each time it is enabled. Use **Test Teams pulse now** to verify that Windows accepted the event and reset its idle timer. These modes are best-effort and cannot override Microsoft or organizational presence policies.

Settings are stored in `%LOCALAPPDATA%\AwakeAndAvailable\settings.json`.

## Portugal work schedule

- The schedule turns PC wake prevention and Teams pulses on at 09:00 and off at 18:00 Portugal time.
- A manual change to either control overrides the schedule until the next 09:00 or 18:00 boundary.
- **Resume automatic schedule now** appears during an override and clears it immediately.
- Uncheck **Automatic schedule · Portugal 09:00–18:00** to keep manual settings indefinitely.
- Safe-point clicking is never restored automatically after restarting the app.

## Icon

The current owl-and-presence app icon is stored in `Assets\awake-available.png`. It deliberately
avoids lightning, battery, charging, and power-button imagery so the tray icon cannot be mistaken
for a system power indicator. To regenerate the multi-resolution Windows icon after changing the
master image, run `Scripts\create-icon.py` with Python and Pillow.
