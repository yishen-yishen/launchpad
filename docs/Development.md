# Development

LaunchDock uses Swift 6, SwiftUI and AppKit, with a minimum deployment target of macOS 26.0. It has no external package dependencies. Open `LaunchDock.xcodeproj` and select the shared `LaunchDock` scheme, or use the commands below on a Mac with Xcode installed.

## Build and run

```sh
sh scripts/build-dev.sh
open build/Development/LaunchDock.app
```

This creates an ad-hoc signed development build. Signing is local; the result is not Developer ID signed or notarized. The project can be regenerated with `python3 scripts/generate-project.py` when changing the generator.

## Checks

```sh
swift test
swift run CoreChecks
sh scripts/check-folder-drag.sh
sh scripts/check-hot-corner.sh
sh scripts/check-wallpaper-no-permission.sh
LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-fullscreen.sh
```

Build the development app before running native checks. Native checks open temporary test windows; run UI check scripts sequentially. They use isolated layouts. Multi-display behavior and physical mouse/trackpad interactions still require manual testing.

## Package

```sh
sh scripts/package-release.sh
```

The universal `.app`, `.dmg`, `.zip`, verification report and SHA-256 checksums are written to `dist/`. These are generated files; publish installers as GitHub Release assets rather than committing them to source control. The packaging script does not imply Developer ID signing or Apple notarization.

## Local data and repository hygiene

Build output, compiler indexes, editor settings, signing material, local app metadata, personal layouts and raw promotional captures are excluded by `.gitignore`. Never commit real layout exports or application catalogs. The author's published contact email is intentional.

`.gitignore` does not remove files from earlier commits. Before publishing an existing repository, inspect its history as well as the current files. If using the source-only export prepared for initial publication, initialize a new repository from that export; it contains no `.git` history. Keep the original repository locally if its development history is needed.

The app stores user data in `~/Library/Application Support/app.launchdock.LaunchDock/` and icon caches in `~/Library/Caches/app.launchdock.LaunchDock/`. Do not remove these directories as part of a build or test cleanup.
