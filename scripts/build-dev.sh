#!/bin/sh
# Local ad-hoc signing only; no Developer ID certificate or notarization.
set -eu
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_dir"
products_dir="${1:-$repository_dir/build/Development}"
xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Debug "CONFIGURATION_BUILD_DIR=$products_dir" "OBJROOT=$repository_dir/build/Intermediates" "ARCHS=$(uname -m)" CODE_SIGNING_ALLOWED=NO build
/usr/bin/codesign --force --sign - --identifier app.launchdock.LaunchDock "$products_dir/LaunchDock.app"
/usr/bin/codesign --verify --strict "$products_dir/LaunchDock.app"
# Register this explicit bundle URL without forcing Launch Services to prefer it
# over a user's installed copy with the same bundle identifier.
swift -e 'import AppKit; import CoreServices
let url = URL(fileURLWithPath: CommandLine.arguments.last!)
guard LSRegisterURL(url as CFURL, true) == noErr, let bundle = Bundle(url: url), bundle.bundleIdentifier == "app.launchdock.LaunchDock", let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { fputs("Development app registration or bundle verification failed.\n", stderr); exit(1) }
if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.launchdock.LaunchDock")?.resolvingSymlinksInPath().path != url.resolvingSymlinksInPath().path { print("Note: Launch Services prefers another installed copy; open the development app by its explicit path.") }
' "$products_dir/LaunchDock.app"
