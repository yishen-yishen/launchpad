#!/bin/sh
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
products_dir="${1:-$repository_dir/build/Development}"
helper_root="$(mktemp -d /tmp/launchdock-window-checks.XXXXXX)"
# Keep each run's compiler input, executable and log isolated.
trap 'touch "$helper_root/quit"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Native check diagnostics: %s\n' "$helper_root"
if [ ! -f "$products_dir/LaunchDockCore.o" ]; then
    printf 'Missing build products: %s. Run sh scripts/build-dev.sh first.\n' "$products_dir" >&2
    exit 1
fi
sed 's/@main struct LaunchDockApp/struct LaunchDockApp/' Sources/LaunchDock/App.swift > "$helper_root/App.swift"
xcrun swiftc -swift-version 6 -parse-as-library -I "$products_dir" "$products_dir/LaunchDockCore.o" Sources/LaunchDock/IconCache.swift Sources/LaunchDock/Store.swift Sources/LaunchDock/Grid.swift Sources/LaunchDock/Views.swift Sources/LaunchDock/TransferActions.swift Sources/LaunchDock/HotKey.swift Sources/LaunchDock/HotCornerService.swift Sources/LaunchDock/WallpaperService.swift Sources/LaunchDock/DesktopWallpaperReader.swift Sources/LaunchDock/DirectoryWatcher.swift Sources/LaunchDock/SettingsControls.swift "$helper_root/App.swift" NativeChecks/LaunchIconChecks.swift NativeChecks/InteractionChecks.swift NativeChecks/FullscreenChecks.swift -o "$helper_root/native-checks"
python3 - "$helper_root" <<'PYHELPER'
import pathlib,plistlib,sys
root=pathlib.Path(sys.argv[1])
for name in ['Visible','Hidden','Behind']:
 p=root/(name+'.app')/'Contents'
 (p/'MacOS').mkdir(parents=True)
 (p/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.launchdock.check.'+name+root.name.replace('.',''), 'CFBundleName':name,'CFBundleExecutable':'WindowHelper','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'26.0'}))
PYHELPER
xcrun swiftc -swift-version 6 -parse-as-library NativeChecks/WindowHelper.swift -o "$helper_root/Visible.app/Contents/MacOS/WindowHelper"
cp "$helper_root/Visible.app/Contents/MacOS/WindowHelper" "$helper_root/Hidden.app/Contents/MacOS/WindowHelper"
cp "$helper_root/Visible.app/Contents/MacOS/WindowHelper" "$helper_root/Behind.app/Contents/MacOS/WindowHelper"
run_checks() {
        # A Cocoa CLI belongs to its terminal/Codex activation session. Give
        # Space tests their own Launch Services identity before yielding focus.
        check_app="$helper_root/NativeChecks.app"
        mkdir -p "$check_app/Contents/MacOS"
        cp "$helper_root/native-checks" "$check_app/Contents/MacOS/NativeChecks"
        python3 - "$check_app" <<'PYAPP'
import pathlib,plistlib,sys,uuid
pathlib.Path(sys.argv[1],'Contents','Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'app.launchdock.NativeChecks.'+uuid.uuid4().hex,
 'CFBundleExecutable':'NativeChecks','CFBundlePackageType':'APPL',
 'CFBundleName':'LaunchDock Native Checks','LSMinimumSystemVersion':'26.0'}))
PYAPP
        codesign --force --sign - "$check_app"
        open -n -W -a "$check_app" --stdout "$helper_root/check.log" --stderr "$helper_root/check.log" \
            --env "LAUNCHDOCK_WINDOW_HELPERS=$helper_root" \
            --env "LAUNCHDOCK_FULLSCREEN_HELPER=${LAUNCHDOCK_FULLSCREEN_HELPER:-}" \
            --env "LAUNCHDOCK_CHECK_RESULT=$helper_root/result" \
            --env "LAUNCHDOCK_CHECK_LIFECYCLE=${LAUNCHDOCK_CHECK_LIFECYCLE:-}" \
            --env "LAUNCHDOCK_CHECK_FORCE_FAILURE=${LAUNCHDOCK_CHECK_FORCE_FAILURE:-}" || return $?
        # open -W does not forward the app's exit code. Require its result file.
        if [ ! -f "$helper_root/result" ]; then
            printf 'FAIL: native test app exited without a result.\n' >> "$helper_root/check.log"
            return 1
        fi
        return "$(cat "$helper_root/result")"
}
if run_checks; then
    :
else
    check_status=$?
    cat "$helper_root/check.log"
    exit "$check_status"
fi
cat "$helper_root/check.log"
rg -q "ALL NATIVE CHECKS PASSED" "$helper_root/check.log"
