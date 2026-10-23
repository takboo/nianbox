#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_version=$(tr -d '\n' < VERSION)
release_root=${1:-"$PWD/.local/release/v$release_version"}
mkdir -p "$release_root"
xcodebuild build -project NianBox.xcodeproj -scheme NianBox -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$release_root/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
release_app="$release_root/DerivedData/Build/Products/Release/NianBox.app"
codesign --verify --strict --deep "$release_app"
lipo "$release_app/Contents/MacOS/NianBox" -verify_arch arm64 x86_64
release_python=${NIANBOX_PACKAGING_PYTHON:-python3}
release_dmg="$release_root/NianBox-$release_version-universal.dmg"
"$release_python" Scripts/package_dmg.py --app "$release_app" --output "$release_dmg"
"$release_python" Scripts/package_dmg.py --verify "$release_dmg"
(cd "$release_root" && shasum -a 256 "NianBox-$release_version-universal.dmg" > SHA256SUMS)
