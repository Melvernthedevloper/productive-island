#!/bin/sh
# Builds ProductiveIsland.app — a bundle is required for Calendar / Automation permission prompts.
set -e
cd "$(dirname "$0")"
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
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP — open it with: open $APP"
