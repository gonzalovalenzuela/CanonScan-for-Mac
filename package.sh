#!/bin/zsh
# Compila CanonScan y arma un .dmg para arrastrar a Aplicaciones.
# Builds CanonScan and creates a .dmg to drag into Applications.
set -euo pipefail
cd "${0:A:h}"

VERSION=0.1
mkdir -p dist build/art
OUT="dist/CanonScan-$VERSION.dmg"
WORK=build/dmg

# 1. Íconos y app / Icons and app
swift Tools/make-art.swift build/art >/dev/null
iconutil -c icns build/art/AppIcon.iconset -o Resources/AppIcon.icns
swift Tools/printer-icon.swift build/art/printer-icon.png 1024 >/dev/null
./build.sh

# 2. Ícono del volumen (la impresora) / Volume icon (the printer)
rm -rf "$WORK"
mkdir -p "$WORK/stage" "$WORK/Volume.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s build/art/printer-icon.png --out "$WORK/Volume.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/art/printer-icon.png --out "$WORK/Volume.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/Volume.iconset" -o "$WORK/stage/.VolumeIcon.icns"

# 3. Contenido: la app y un acceso a Aplicaciones / Contents: the app and an Applications link
ditto --norsrc --noextattr build/latest/CanonScan.app "$WORK/stage/CanonScan.app"
ln -s /Applications "$WORK/stage/Applications"

# 4. Imagen de disco comprimida / Compressed disk image
rm -f "$OUT"
hdiutil create -quiet -volname "CanonScan $VERSION" -srcfolder "$WORK/stage" \
  -fs HFS+ -format UDRW "$WORK/rw.dmg"
MNT=$(hdiutil attach -nobrowse -noautoopen "$WORK/rw.dmg" | awk -F'\t' '/\/Volumes\// {print $NF}')
SetFile -a C "$MNT" 2>/dev/null || xattr -wx com.apple.FinderInfo \
  "0000000000000000040000000000000000000000000000000000000000000000" "$MNT"
hdiutil detach -quiet "$MNT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"

# 5. Ícono del archivo .dmg en Finder / Finder icon for the .dmg file
swift Tools/set-icon.swift build/art/printer-icon.png "$OUT"

rm -rf "$WORK"
echo "OK: ${OUT:A}"
