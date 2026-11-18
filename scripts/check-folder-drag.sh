#!/bin/sh
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
check_dir="$(mktemp -d /tmp/launchdock-folder-drag.XXXXXX)"
sed 's/@main struct LaunchDockApp/struct LaunchDockApp/' Sources/LaunchDock/App.swift > "$check_dir/App.swift"
xcrun swiftc -swift-version 6 -parse-as-library -I build/Development build/Development/LaunchDockCore.o Sources/LaunchDock/IconCache.swift Sources/LaunchDock/Store.swift Sources/LaunchDock/Grid.swift Sources/LaunchDock/Views.swift Sources/LaunchDock/TransferActions.swift Sources/LaunchDock/HotKey.swift Sources/LaunchDock/HotCornerService.swift Sources/LaunchDock/WallpaperService.swift Sources/LaunchDock/DesktopWallpaperReader.swift Sources/LaunchDock/DirectoryWatcher.swift Sources/LaunchDock/SettingsControls.swift "$check_dir/App.swift" NativeChecks/FolderDragChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
