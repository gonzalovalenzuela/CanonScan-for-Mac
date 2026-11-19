#!/bin/zsh
# Compila la app y arma el instalador con título, fondo e ícono.
# Builds the app and creates the installer with title, background and icon.
set -euo pipefail
cd "${0:A:h}"

VERSION=0.1
ID=cl.local.canonscan.pkg
mkdir -p dist
OUT="dist/CanonScan-$VERSION.pkg"
WORK=build/installer

# 1. Arte (ícono y fondos) y app / Artwork (icon and backgrounds) and app
mkdir -p build/art
swift Tools/printer-icon.swift build/art/installer-icon.png 1024 >/dev/null
swift Tools/make-art.swift build/art build/art/installer-icon.png >/dev/null
iconutil -c icns build/art/AppIcon.iconset -o Resources/AppIcon.icns
./build.sh

# 2. Paquete de componente / Component package
rm -rf "$WORK"
mkdir -p "$WORK/root/Applications" "$WORK/resources/en.lproj" "$WORK/resources/es.lproj"
ditto --norsrc --noextattr "build/latest/CanonScan.app" "$WORK/root/Applications/CanonScan.app"
xattr -cr "$WORK/root"
# Sin relocalización: si no, Installer "actualiza" cualquier copia con el mismo
# identificador (p. ej. en build/) en vez de instalar en /Applications.
# No relocation: otherwise Installer "updates" any copy with the same
# identifier (e.g. in build/) instead of installing into /Applications.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
COPYFILE_DISABLE=1 pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
  --identifier "$ID" --version "$VERSION" \
  --ownership recommended --install-location / "$WORK/component.pkg" >/dev/null

# 3. Recursos del instalador / Installer resources
cp build/art/background.png build/art/background-dark.png "$WORK/resources/"
print -r -- '"SU_TITLE" = "Canon Scanner";' > "$WORK/resources/en.lproj/Localizable.strings"
print -r -- '"SU_TITLE" = "Escáner Canon";' > "$WORK/resources/es.lproj/Localizable.strings"

cat > "$WORK/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>SU_TITLE</title>
    <background file="background.png" mime-type="image/png" alignment="bottomleft" scaling="proportional"/>
    <background-darkAqua file="background-dark.png" mime-type="image/png" alignment="bottomleft" scaling="proportional"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default"><line choice="$ID"/></line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$ID" visible="false"><pkg-ref id="$ID"/></choice>
    <pkg-ref id="$ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
EOF

# 4. Instalador final / Final installer
rm -f "$OUT"
COPYFILE_DISABLE=1 productbuild --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" --package-path "$WORK" "$OUT" >/dev/null

# 5. Ícono del archivo .pkg en Finder / Finder icon for the .pkg file
swift Tools/set-icon.swift build/art/installer-icon.png "$OUT"

rm -rf "$WORK"
echo "OK: ${OUT:A}"
