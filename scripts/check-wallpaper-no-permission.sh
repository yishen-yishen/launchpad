#!/bin/sh
set -eu
probe_root="$(mktemp -d /tmp/launchdock-wallpaper-probe.XXXXXX)"
probe_app="$probe_root/WallpaperReadProbe.app"
mkdir -p "$probe_app/Contents/MacOS"
python3 - "$probe_app" <<'PYINFO'
import pathlib,plistlib,sys,uuid
pathlib.Path(sys.argv[1],'Contents','Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'app.launchdock.WallpaperReadProbe.'+uuid.uuid4().hex,
 'CFBundleExecutable':'WallpaperReadProbe','CFBundlePackageType':'APPL',
 'CFBundleName':'WallpaperReadProbe','LSUIElement':True,'LSMinimumSystemVersion':'26.0'}))
PYINFO
xcrun swiftc -swift-version 6 -parse-as-library Sources/LaunchDock/DesktopWallpaperReader.swift Sources/LaunchDock/WallpaperService.swift NativeChecks/WallpaperReadProbe.swift -o "$probe_app/Contents/MacOS/WallpaperReadProbe"
codesign --force --sign - "$probe_app"
open -n "$probe_app" --args "$probe_root/result.json"
probe_attempt=0
while [ ! -f "$probe_root/result.json" ] && [ "$probe_attempt" -lt 100 ]; do
    sleep 0.1
    probe_attempt=$((probe_attempt+1))
done
python3 - "$probe_root/result.json" <<'PYRESULT'
import json,pathlib,sys
result=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(json.dumps(result,ensure_ascii=False))
assert result['screenRecordingGranted'] is False, 'Probe must have no Screen Recording grant'
assert result.get('hasContent') is True, 'Must obtain real non-black wallpaper pixels'
assert result['meanAlpha'] > 0.99
print('PASS: real desktop wallpaper pixels without Screen Recording authorization')
PYRESULT
