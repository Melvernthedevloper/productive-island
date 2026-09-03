#!/bin/sh
# Builds ProductiveIsland.app — a bundle is required for Calendar / Automation permission prompts.
set -e
cd "$(dirname "$0")"
if [ "$1" = "--make-cert" ]; then
  T=$(mktemp -d)
  openssl req -x509 -newkey rsa:2048 -keyout "$T/k.pem" -out "$T/c.pem" -days 3650 -nodes -subj "/CN=ProductiveIsland Dev" \
    -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" 2>/dev/null
  openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/p.p12" -passout pass:pi -legacy 2>/dev/null || \
  openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/p.p12" -passout pass:pi
  security import "$T/p.p12" -k ~/Library/Keychains/login.keychain-db -P pi -T /usr/bin/codesign
  security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$T/c.pem"
  rm -rf "$T"
  echo "certificate 'ProductiveIsland Dev' installed."
  echo "The first build will show a keychain prompt for codesign — click 'Always Allow' once."
  exit 0
fi
swift build -c release
APP=ProductiveIsland.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/ProductiveIsland "$APP/Contents/MacOS/"
# icon: the working sprite, rendered by the app itself
ICON=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICON"
.build/release/ProductiveIsland --icon "$ICON/icon_512x512@2x.png"
for s in 16 32 128 256 512; do sips -z $s $s "$ICON/icon_512x512@2x.png" --out "$ICON/icon_${s}x${s}.png" >/dev/null; sips -z $((s*2)) $((s*2)) "$ICON/icon_512x512@2x.png" --out "$ICON/icon_${s}x${s}@2x.png" >/dev/null; done
mkdir -p "$APP/Contents/Resources"; iconutil -c icns "$ICON" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.raff.productiveisland</string>
  <key>CFBundleName</key><string>Productive Island</string>
  <key>CFBundleExecutable</key><string>ProductiveIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Shows your next event in the island.</string>
  <key>NSAppleEventsUsageDescription</key><string>Controls Spotify playback.</string>
</dict></plist>
PLIST
# Sign with a stable local identity when one exists, so macOS permissions survive rebuilds.
# Create it once with: ./make-app.sh --make-cert
if security find-identity -v -p codesigning 2>/dev/null | grep -q "ProductiveIsland Dev"; then
  codesign --force --sign "ProductiveIsland Dev" "$APP" >/dev/null 2>&1
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "note: ad-hoc signed — permissions reset on every rebuild. Run ./make-app.sh --make-cert once to fix."
fi
echo "built $APP — open it with: open $APP"
