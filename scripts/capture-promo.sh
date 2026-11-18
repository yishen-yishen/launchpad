#!/bin/sh
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
producer_dir="$repository_dir/build/Promo"
producer_app="$producer_dir/PromoCapture.app"
mkdir -p "$producer_app/Contents/MacOS" "$repository_dir/media/launchdock-promo/frames"
sed 's/@main struct LaunchDockApp/struct LaunchDockApp/' Sources/LaunchDock/App.swift > "$producer_dir/App.swift"
python3 - "$producer_app" <<'PY'
import pathlib,plistlib,sys
pathlib.Path(sys.argv[1],'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.launchdock.PromoCapture','CFBundleExecutable':'PromoCapture','CFBundlePackageType':'APPL','LSUIElement':True,'LSMinimumSystemVersion':'26.0'}))
PY
xcrun swiftc -swift-version 6 -parse-as-library -I build/Development build/Development/LaunchDockCore.o Sources/LaunchDock/IconCache.swift Sources/LaunchDock/Store.swift Sources/LaunchDock/Grid.swift Sources/LaunchDock/Views.swift Sources/LaunchDock/TransferActions.swift Sources/LaunchDock/HotKey.swift Sources/LaunchDock/HotCornerService.swift Sources/LaunchDock/WallpaperService.swift Sources/LaunchDock/DesktopWallpaperReader.swift Sources/LaunchDock/DirectoryWatcher.swift Sources/LaunchDock/SettingsControls.swift "$producer_dir/App.swift" Promo/Capture.swift -o "$producer_app/Contents/MacOS/PromoCapture"
codesign --force --sign - "$producer_app"
: > "$producer_dir/capture.log"
open -n -W -a "$producer_app" --stdout "$producer_dir/capture.log" --stderr "$producer_dir/capture.log" --args "$repository_dir/media/launchdock-promo/frames" "$@"
cat "$producer_dir/capture.log"
rg -q 'CAPTURE COMPLETE' "$producer_dir/capture.log"
