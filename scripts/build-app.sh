#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Este build precisa de macOS e Xcode instalado.' >&2
  exit 1
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/loock-release.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
xcodebuild -project Gergelim.xcodeproj -scheme Gergelim -configuration Release \
  -derivedDataPath "$build_dir" ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO build
app_path="$build_dir/Build/Products/Release/Gergelim.app"
test -x "$app_path/Contents/MacOS/Gergelim"
/usr/bin/lipo "$app_path/Contents/MacOS/Gergelim" -verify_arch x86_64
xcrun swiftc LoockMesa/Eko/GergelimSeed.swift scripts/GenerateSeedIcon.swift -o "$build_dir/seed-icon"
"$build_dir/seed-icon" "$build_dir/AppIcon.iconset" "Resources/AppIconSource.jpg"
/usr/bin/iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --verify --strict "$app_path/Contents/MacOS/OSDGuardian"
/usr/bin/codesign --force --sign - --entitlements LoockMesa/LoockMesa.entitlements "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
mkdir -p dist
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive_path="dist/Gergelim-${app_version}-Intel.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
echo "Aplicativo compilado: $archive_path"
