#!/bin/sh
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
products_dir="${1:-$repository_dir/build/Development}"
xcrun swiftc -swift-version 6 -parse-as-library -I "$products_dir" "$products_dir/LaunchDockCore.o" Sources/LaunchDock/HotCornerService.swift NativeChecks/HotCornerChecks.swift -o /tmp/launchdock-hot-corner-checks
/tmp/launchdock-hot-corner-checks
