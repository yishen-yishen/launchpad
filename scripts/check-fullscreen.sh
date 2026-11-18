#!/bin/sh
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
helper_root="$(mktemp -d /tmp/launchdock-fullscreen.XXXXXX)"
helper_app="$helper_root/FullscreenHelper.app"
# Also ask the helper to close if the driver is interrupted or crashes.
trap 'touch "$helper_root/quit"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Fullscreen check diagnostics: %s\n' "$helper_root"
mkdir -p "$helper_app/Contents/MacOS"
python3 - "$helper_app" <<'PYINFO'
import pathlib,plistlib,sys,uuid
pathlib.Path(sys.argv[1],'Contents','Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'app.launchdock.FullscreenHelper.'+uuid.uuid4().hex,
 'CFBundleExecutable':'FullscreenHelper','CFBundlePackageType':'APPL',
 'CFBundleName':'LaunchDock Fullscreen Test','LSMinimumSystemVersion':'26.0'}))
PYINFO
xcrun swiftc -swift-version 6 -parse-as-library NativeChecks/FullscreenHelper.swift -o "$helper_app/Contents/MacOS/FullscreenHelper"
codesign --force --sign - "$helper_app"
LAUNCHDOCK_FULLSCREEN_HELPER="$helper_app" sh scripts/check-native.sh "${1:-$repository_dir/build/Development}"
