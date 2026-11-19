#!/bin/zsh
# Compila CanonScan y su puente AirScan como apps universales (arm64 + x86_64)
# con firma ad-hoc.
# Builds CanonScan and its AirScan bridge as universal apps (arm64 + x86_64)
# with ad-hoc signing.
#
# Cada compilación va a una carpeta nueva build/app-<fecha>: macOS no deja
# modificar una app ya abierta (protección «Gestión de apps»).
# Each build goes to a new build/app-<date> folder: macOS won't let a
# launched app be modified (App Management protection).
set -euo pipefail
cd "${0:A:h}"

OUTDIR="build/app-$(date +%Y%m%d-%H%M%S)"
APP="$OUTDIR/CanonScan.app"
BRIDGE="$APP/Contents/Library/LoginItems/CanonScanBridge.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Compila un ejecutable universal / Builds a universal executable
universal() {
  local name=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
      -sdk "$(xcrun --show-sdk-path)" -parse-as-library \
      -o "$TMP/$name-$arch" "$@"
  done
  lipo -create "$TMP/$name-arm64" "$TMP/$name-x86_64" -output "$TMP/$name"
}

universal CanonScan Sources/Shared/*.swift Sources/App/*.swift
universal CanonScanBridge Sources/Shared/*.swift Sources/Bridge/*.swift

# Puente (barra de menú) / Bridge (menu bar)
mkdir -p "$BRIDGE/Contents/MacOS" "$BRIDGE/Contents/Resources"
cp "$TMP/CanonScanBridge" "$BRIDGE/Contents/MacOS/"
cp Resources/Bridge/Info.plist "$BRIDGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BRIDGE/Contents/Resources/"
for lang in en es; do
  mkdir -p "$BRIDGE/Contents/Resources/$lang.lproj"
  cp "Resources/$lang.lproj/Localizable.strings" "$BRIDGE/Contents/Resources/$lang.lproj/"
  cp "Resources/Bridge/$lang.lproj/InfoPlist.strings" "$BRIDGE/Contents/Resources/$lang.lproj/"
done

# App principal / Main app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/CanonScan" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LICENSES.txt Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/es.lproj "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

# Firma de adentro hacia afuera / Sign inside out
codesign --force --sign - --timestamp=none "$BRIDGE"
codesign --force --sign - --timestamp=none "$APP"

# Enlace a la última compilación / Link to the latest build
ln -sfn "${OUTDIR:t}" build/latest
echo "OK: $APP"
