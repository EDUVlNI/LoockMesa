#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Este build precisa de macOS e Xcode instalado.' >&2
  exit 1
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/loock-release.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
xcodebuild -project LoockMesa.xcodeproj -scheme LoockMesa -configuration Release \
  -derivedDataPath "$build_dir" ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO build
app_path="$build_dir/Build/Products/Release/LoockMesa.app"
test -x "$app_path/Contents/MacOS/LoockMesa"
/usr/bin/lipo "$app_path/Contents/MacOS/LoockMesa" -verify_arch x86_64
/usr/bin/codesign --force --sign - --entitlements LoockMesa/LoockMesa.entitlements "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
mkdir -p dist
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" dist/LoockMesa-0.32.0-Intel.zip
echo 'Aplicativo compilado: dist/LoockMesa-0.32.0-Intel.zip'
