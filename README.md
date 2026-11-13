# Remoty

A native macOS menu bar remote for Android TV projectors. It uses the same popover layout as the LG webOS app and talks to the projector through `adb` over the network.

This is a community project, independent of Google and of any projector vendor.

## Download

**[Download Remoty for Mac (latest release)](https://github.com/atapinar/Remoty/releases/latest/download/Remoty-macOS-arm64.zip)** · [all releases](https://github.com/atapinar/Remoty/releases)

Requires macOS 14 or later on Apple Silicon, plus `adb` (`brew install android-platform-tools`).

The app is not notarized by Apple. To open it the first time: unzip, drag `Remoty.app` to Applications, then right-click it and choose **Open** (or run `xattr -dr com.apple.quarantine /Applications/Remoty.app`).

## Tested versions

| Android TV version | Status |
| --- | --- |
| 13 | Read-only queries verified on one projector: power state, volume, foreground app, app list, brightness |

Commands that change state (key events, volume, app launch, brightness) use standard Android shell commands. They are not yet verified on a device.

## Requirements

- A Mac running macOS 14 or later.
- Xcode Command Line Tools with Swift 5.9 or later: `xcode-select --install`.
- `adb`: `brew install android-platform-tools`. The app looks in `/opt/homebrew/bin`, `/usr/local/bin`, then `PATH`.
- On the projector: Developer options with **Network debugging** (ADB over network) turned on.

## Build and run

```sh
bash scripts/build.sh
open "dist/Remoty.app"
```

## Connect

1. Open the app from the menu bar, then open Settings.
2. Choose **Find projectors on your network**, or enter the projector's IPv4 address or its `.local` name. Port 5555 is the default. Add `:port` for another port.
3. Choose **Save and connect**.
4. The first time, the projector shows a USB debugging prompt. Choose **Always allow from this computer** on the projector.

The address and name are stored in the app's preferences on this Mac. The project ships with no device address.

## Features

- **Your projector:** the foreground app, volume card with slider and +/-, favorite apps, inputs (HDMI 1, HDMI 2, input menu).
- **Remote:** d-pad, OK, back, home, menu, settings, play/pause, rewind, fast forward, and a keyboard field that sends `input text`.
- **Apps:** apps with a TV launcher entry, plus installed favorites. Star an app to pin it. Defaults: YouTube, Netflix, Prime Video, MX Player.
- **Mirror:** opens Displays settings with guidance for AirPlay screen mirroring.
- **Activity:** local screen time from the foreground app, recorded while the Mac is awake and connected and the projector is awake.
- **Picture:** brightness through `settings system screen_brightness` (0-255). Contrast, color, sharpness, keystone and focus are placeholders until the vendor commands are known.

## Checks

```sh
"dist/Remoty.app/Contents/MacOS/Remoty" --self-check
"dist/Remoty.app/Contents/MacOS/Remoty" --probe PROJECTOR_IP
```

`--self-check` runs offline parser tests. `--probe` runs read-only `adb` queries and prints the parsed values. Do not paste probe output into issues without removing device details.

## Limits

- Power uses `KEYCODE_SLEEP` and `KEYCODE_WAKEUP`. If the projector drops off the network in standby, the app cannot wake it.
- Mute sends `KEYCODE_VOLUME_MUTE`. The mute state on screen is a local guess.
- HDMI keycodes work only if the projector firmware maps them.
- App icons are drawn from SF Symbols and initials. The app does not pull icons from the device.
