#!/bin/sh
# Builds a standalone preview. No Developer ID or notarization is implied.
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
release_version=0.0.1-beta
bundle_version=0.0.1
release_build=2026111301
products_dir="$repository_dir/build/DistributionProducts"
output_dir="$repository_dir/dist"
work_dir="$(mktemp -d "$repository_dir/build/package.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$output_dir"
xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Release \
    "OBJROOT=$repository_dir/build/DistributionIntermediates" \
    "CONFIGURATION_BUILD_DIR=$products_dir" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
app="$work_dir/LaunchDock.app"
ditto "$products_dir/LaunchDock.app" "$app"
mkdir -p "$app/Contents/Resources"
swift scripts/make-app-icon.swift "$work_dir/LaunchDock.iconset"
iconutil -c icns "$work_dir/LaunchDock.iconset" -o "$app/Contents/Resources/LaunchDock.icns"
python3 - "$app/Contents/Info.plist" "$bundle_version" "$release_build" "$release_version" <<'PYINFO'
import pathlib,plistlib,sys
path=pathlib.Path(sys.argv[1]); info=plistlib.loads(path.read_bytes())
info.update(CFBundleShortVersionString=sys.argv[2], CFBundleVersion=sys.argv[3], CFBundleIconFile='LaunchDock.icns', LaunchDockDisplayVersion=sys.argv[4])
path.write_bytes(plistlib.dumps(info))
PYINFO
codesign --force --sign - --options runtime --identifier app.launchdock.LaunchDock "$app"
python3 scripts/verify-release.py "$app" > "$work_dir/Verification.json"
# Copy only the self-contained app, never build products or user data.
if [ -e "$output_dir/LaunchDock.app" ]; then rm -rf "$output_dir/LaunchDock.app"; fi
ditto "$app" "$output_dir/LaunchDock.app"
python3 scripts/verify-release.py "$output_dir/LaunchDock.app" > "$output_dir/Verification.json"
base="LaunchDock-$release_version-universal"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/$base.zip"
mkdir -p "$work_dir/Image"
ditto "$app" "$work_dir/Image/LaunchDock.app"
ln -s /Applications "$work_dir/Image/Applications"
cp Packaging/安装说明.txt "$work_dir/Image/安装说明.txt"
cp Packaging/安装说明.txt "$output_dir/安装说明.txt"
hdiutil create -ov -format UDZO -fs HFS+ -volname 'LaunchDock' -srcfolder "$work_dir/Image" "$output_dir/$base.dmg"
hdiutil verify "$output_dir/$base.dmg"
(cd "$output_dir" && shasum -a 256 "$base.dmg" "$base.zip" > SHA256SUMS.txt)
printf 'Standalone preview ready: %s/%s.dmg\n' "$output_dir" "$base"
