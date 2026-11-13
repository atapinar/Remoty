# Remoty: setup guide for Claude

This is a native macOS menu bar app that controls an Android TV projector through `adb`. Follow these steps in order. Ask the user for anything you cannot find. Do not guess an IP address.

## 1. Check the Mac

- macOS 14 or later: `sw_vers -productVersion`.
- Swift 5.9 or later: `swift --version`. If it is missing, tell the user to run `xcode-select --install`.
- adb: `command -v adb`. If it is missing, run `brew install android-platform-tools`.

## 2. Build the app

```sh
bash scripts/build.sh
```

The output is `dist/Remoty.app`. Do not commit `dist/`.

## 3. Run the offline check

```sh
"dist/Remoty.app/Contents/MacOS/Remoty" --self-check
```

## 4. Prepare the projector

The user turns on Developer options and Network debugging on the projector. The first connection shows an authorization prompt on the projector. The user must accept it there.

## 5. Read-only probe

```sh
"dist/Remoty.app/Contents/MacOS/Remoty" --probe PROJECTOR_IP
```

This sends only read-only queries.

## 6. Connect in the app

Open the app, open Settings, find the projector or enter its IPv4 address or `.local` name, then choose **Save and connect**.

## Rules

- Never write the user's IP address, MAC address, serial number or model into a tracked file. Keep them in the app's settings or in `.local/`.
- Ask before you send any command that changes the projector's state: key events, `settings put`, app launches, volume changes.
- Do not add code comments.
- Never commit or push without the user's explicit approval.
