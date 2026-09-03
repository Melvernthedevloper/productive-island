#!/bin/sh
# Builds ProductiveIsland.dmg: the app plus an Applications shortcut. Drag to install.
set -e
cd "$(dirname "$0")"
./make-app.sh
V=$(defaults read "$PWD/ProductiveIsland.app/Contents/Info" CFBundleShortVersionString)
T=$(mktemp -d); cp -R ProductiveIsland.app "$T/"; ln -s /Applications "$T/Applications"
rm -f "ProductiveIsland-$V.dmg"
hdiutil create -volname "Productive Island" -srcfolder "$T" -ov -format UDZO "ProductiveIsland-$V.dmg" >/dev/null
rm -rf "$T"; echo "built ProductiveIsland-$V.dmg"
