# NianBox · 念匣

**Give a passing thought somewhere to stay.**

NianBox lives in your Mac's menu bar. Move to a screen corner or press `Control–Option–Space`, write a line, and return to what you were doing. Start offline; connect your own server when you want Hermes to work with the same tasks.

[![Release](https://img.shields.io/github/v/release/takboo/nianbox)](https://github.com/takboo/nianbox/releases/latest)
[![CI](https://github.com/takboo/nianbox/actions/workflows/ci.yml/badge.svg)](https://github.com/takboo/nianbox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[**Download for Mac**](https://github.com/takboo/nianbox/releases/latest) · [Get started](#get-started) · [Usage guide (中文)](docs/usage.md) · [简体中文](README.md)

<p align="center"><img src="NianBox/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="NianBox's drawer and folded note icon"></p>

## What NianBox does

### Capture now, organize when you have time

A title is enough to save. Keep actionable items in Tasks and unscheduled ideas in Backlog. Set a priority, start working, or mark an item complete when ready. Completed tasks stay in your history until you explicitly delete them.

Tasks and Backlog each retain their unsubmitted draft when you switch between them. Saved items remain on your Mac, so capture works offline.

### Know when it is saved and when it is synced

The menu-bar note responds to capture and local saving. A separate brief acknowledgement confirms synchronization. Connection failures, local save failures and deletion conflicts have distinct shapes and text status.

Background checks stay quiet when nothing changes. With macOS Reduce Motion enabled, static symbols convey the same states.

### Continue between your Mac and Hermes

Connect a self-hosted NianBox Server to let Hermes capture, find or complete tasks, then return to your Mac to see them. The server runs independently; on an always-on device, it remains available to Hermes while your Mac is off.

Your server holds the shared data and your Mac keeps an offline copy. Saved changes remain queued for retry when synchronization is interrupted.

## Get started

Requires **macOS 14 or later**, on Apple Silicon or Intel.

1. Download the Universal DMG from [GitHub Releases](https://github.com/takboo/nianbox/releases/latest), open it, and drag NianBox to Applications.
2. Launch from Applications. Move to the default top-right screen corner or press `Control–Option–Space` to capture.
3. Enter a title and press Return to save. Open Settings from the menu bar or panel gear to change the corner, transparency and capture shortcut.

This open-source build is ad-hoc signed and **not Apple-notarized**. macOS may block the first downloaded launch. After checking the source, review System Settings → Privacy & Security → Open Anyway. Keep system security protections enabled.

For cross-device use, follow the [deployment guide (中文)](docs/deployment.md), enter the server URL and token in Mac settings, then [connect Hermes (中文)](docs/hermes.md). Local capture works without a server.

Unsubmitted drafts last for the current App session only; save before quitting. Due dates support display and queries; **scheduled notifications are not implemented**.

## Learn more

- **Everyday use and questions:** [usage guide (中文)](docs/usage.md) or [open an issue](https://github.com/takboo/nianbox/issues).
- **Hosting and backups:** [deployment (中文)](docs/deployment.md), [Hermes setup (中文)](docs/hermes.md).
- **Changes:** [release notes](https://github.com/takboo/nianbox/releases).
- **Development:** [development guide (中文)](docs/development.md), [documentation index (中文)](docs/README.md), and [verification scope (中文)](docs/verification.md).

## Credits and license

NianBox is based on Emanuele Di Pietro's [Peekaboo](https://github.com/Emanuele-web04/Peekaboo), retaining its macOS corner-panel interaction and original attribution. NianBox uses its own local data directory and independent server; old Peekaboo stores are not migrated automatically.

Licensed under [MIT](LICENSE).
