#!/bin/zsh
# Compila Escáner Canon como app universal (arm64 + x86_64) y la firma ad-hoc.
# Builds Escáner Canon as a universal app (arm64 + x86_64) with ad-hoc signing.
#
# Cada compilación va a una carpeta nueva build/app-<fecha>: macOS no deja
# modificar una app ya abierta (protección «Gestión de apps»).
# Each build goes to a new build/app-<date> folder: macOS won't let a
# launched app be modified (App Management protection).
set -euo pipefail
cd "${0:A:h}"

OUTDIR="build/app-$(date +%Y%m%d-%H%M%S)"
# Nombre de carpeta ASCII: pkgbuild/mkbom fallan con acentos en la ruta.
# ASCII folder name: pkgbuild/mkbom fail with accents in the path.
APP="$OUTDIR/CanonScan.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -sdk "$(xcrun --show-sdk-path)" -parse-as-library \
    -o "$TMP/CanonScan-$arch" Sources/*.swift
done
lipo -create "$TMP/CanonScan-arm64" "$TMP/CanonScan-x86_64" -output "$APP/Contents/MacOS/CanonScan"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LICENSES.txt "$APP/Contents/Resources/"
# Traducciones es / en / Translations es / en
cp -R Resources/*.lproj "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

codesign --force --sign - --timestamp=none "$APP"
# Enlace a la última compilación / Link to the latest build
ln -sfn "${OUTDIR:t}" build/latest
echo "OK: $APP"
