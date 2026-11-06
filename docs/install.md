# Install macino

[← Home](../README.md)

## Before you start

Use a Mac with Apple silicon (M1 or later) running macOS 14 or newer. The release
DMG contains an arm64 app. Some features depend on hardware, macOS permissions or
a connected Android device. Unsupported CPU temperature sensors are hidden.

## Install

1. Open [Releases](https://github.com/ArianAtri/macino/releases) and choose the
   latest release. Download `macino-1.0.0-arm64.dmg` for version 1.0.0.
2. Open the DMG. Drag **macino.app** onto **Applications**.
3. Wait for Finder to finish copying, then open **Applications → macino**.
4. Look for the macino icon in the menu bar. Open **Settings** if you want it to
   launch when you log in.
5. Eject the macino disk image when you’re done. You only need the installed app.

The app does not launch itself after a Finder drag-and-drop installation.

## If macOS warns about the download

This release is locally signed and has not been notarized by Apple. If you know
and trust where it came from, try opening it once, then use **System Settings →
Privacy & Security → Open Anyway** if macOS offers that option. Follow the macOS
confirmation. Do not disable Gatekeeper or remove quarantine system-wide.

## Update

Quit macino from its menu, drag the new app into Applications and choose Replace.
Then open the installed copy. Settings are retained. Clipboard history is
memory-only, so quitting clears it. A new local build may require macOS to approve
Accessibility again because its signature has changed.

## Clipboard shortcut

In **Clipboard**, enable history and **Keyboard shortcut**. The default is
**⌃V (Control + V)**, not Command + V. Click the shortcut button to record another
combination, or use **Use ⌃V** to restore the default. Ordinary shortcuts can open
the list without Accessibility. Without that permission, picking an item copies
it; use **⌘V** in the destination app to paste.

To allow cursor positioning and automatic paste, enable macino in **System
Settings → Privacy & Security → Accessibility**. macino does not open this screen
or request the permission automatically. Fn shortcuts need that permission and a
keyboard that sends Fn to macOS.

## Remove

Turn off launch at login, quit macino and move `/Applications/macino.app` to Trash.
The clipboard’s in-memory history is gone when the app quits. Saved preferences
are retained unless you remove them separately.
