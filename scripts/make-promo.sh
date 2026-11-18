#!/bin/sh
# Reuse captured native frames; pass --capture to record the isolated demo again.
set -eu
repository_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_dir"
mkdir -p build/Promo media/launchdock-promo
if [ "${1:-}" = "--capture" ]; then
    sh scripts/capture-promo.sh
fi
xcrun swiftc -swift-version 6 -parse-as-library Promo/Render.swift -o build/Promo/render-promo
xcrun swiftc -swift-version 6 -parse-as-library Promo/Verify.swift -o build/Promo/verify-promo
build/Promo/render-promo
build/Promo/verify-promo
shasum -a 256 media/LaunchDock-Promo-1080p.mp4 > media/launchdock-promo/SHA256SUMS.txt
