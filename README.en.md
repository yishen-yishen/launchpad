# LaunchDock

English | [简体中文](README.md)

**Your everyday apps, within easy reach.**

LaunchDock is a native macOS app launcher. Browse a familiar icon grid, find apps by name, and organize your favorite tools with drag and drop.

## Features

- **Quick access**: Open the launcher from the Dock, menu bar, keyboard shortcut, or a hot corner.
- **Instant search**: Type an app name to find and launch it.
- **Drag to organize**: Rearrange icons or drop one app onto another to create a folder. Open a folder and click its title to rename it.
- **Move apps out of folders**: Drag outside a folder and pause for about 300ms to return to the main page, then keep dragging to choose a destination.
- **Page navigation**: Use the mouse wheel, trackpad, a horizontal drag on empty space, or the page dots.
- **A familiar desktop feel**: Automatically reads and blurs your wallpaper. Customize icon size, hide the Dock or menu bar icon, and launch at login.
- **Keep your layout**: Arrangements save automatically, with layout import, export, and undo for the latest organization change.

## Install

Requires **macOS 26.0 or later**. The universal build supports Apple Silicon and Intel Macs compatible with that macOS version. No Xcode, Homebrew, or additional dependencies are needed.

1. Check [Releases](https://github.com/yishen-yishen/launchpad/releases) for `LaunchDock-0.0.1-beta-universal.dmg`.
2. Quit any running copy of LaunchDock, open the DMG, and drag **LaunchDock** into **Applications**.
3. Eject the disk image and open LaunchDock from Applications.

The current version is **0.0.1-beta**, ad-hoc signed and not yet notarized by Apple. If macOS blocks the first launch, verify that you trust the download source, then follow the prompts in **System Settings → Privacy & Security** to open it. You do not need to disable system security protections.

## Getting started

| Action | How |
| --- | --- |
| Show / hide the launcher | Press `Option + Space` by default, or click its Dock / menu bar icon |
| Configure a hot corner | Choose a corner in Settings → General; entering it toggles the launcher |
| Launch an app | Click its icon or name, or search by name first |
| Organize apps | Drag icons directly; drop one app onto another to create a folder |
| Close a folder | Click outside the folder or press `Esc` |
| Open settings | Use the button beside the search field, or right-click empty space and choose Settings |
| Reveal an app in Finder | Right-click an app and choose Show in Finder |

While searching, `Esc` clears the search first. After installing or removing apps, you can rescan in Settings → Apps. If you hide both the Dock and menu bar icons, keep a working shortcut or hot corner enabled.

The current interface is primarily in Simplified Chinese; this English guide describes the same controls.

## Privacy and data

LaunchDock requires no account and includes no online service or telemetry. App discovery, search, layouts, and icon caching run locally. Wallpaper access does not request Screen Recording permission.

Replacing the `.app` during an upgrade keeps your layout. To uninstall, quit LaunchDock and move it to the Trash. Personal layouts remain in `~/Library/Application Support/app.launchdock.LaunchDock/`. Exported layouts may contain information about installed apps; review them before sharing.

## Feedback and contact

Report problems or suggestions through [Issues](https://github.com/yishen-yishen/launchpad/issues). Include your macOS version and steps to reproduce. Avoid attaching personal layouts, logs, or screenshots containing private information.

Author: [yishen@mdashen.com](mailto:yishen@mdashen.com)

For local builds and development, see [Development](docs/Development.md).
