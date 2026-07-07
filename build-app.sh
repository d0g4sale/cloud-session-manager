#!/bin/zsh
# Builds "Cloud Session Manager.app" from the SwiftPM package.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="Cloud Session Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CloudSessionManager "$APP/Contents/MacOS/CloudSessionManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run it with: open $APP"
