#!/bin/bash
# Builds "Tac Map Overlay.app" for Apple Silicon Macs. Needs only the Xcode command line tools (swiftc).
#   usage:  bash mac/build.sh [version]        (default: the number in mac/VERSION)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
APP="build/Tac Map Overlay.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling v$VERSION ..."
swiftc -O -target arm64-apple-macos12.0 \
    -o "$APP/Contents/MacOS/TacMapOverlay" \
    Sources/*.swift \
    -framework Cocoa -framework WebKit -framework Carbon

cp Resources/default-tablet.png "$APP/Contents/Resources/default-tablet.png"

sed "s/__VERSION__/$VERSION/g" Info.plist.template > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature (free; required for Apple Silicon to run the app at all). It is not an Apple-notarized signature.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

ZIP="build/TacMapOverlay-mac-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Done: mac/$ZIP"
