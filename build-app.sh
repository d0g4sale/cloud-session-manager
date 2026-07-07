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

# Stamp the version into the bundled Info.plist. CI sets these (APP_VERSION from
# the release tag, BUILD_NUMBER from the run); locally they default to whatever
# Info.plist already carries, so a plain ./build-app.sh still works.
PLIST="$APP/Contents/Info.plist"
if [ -n "${APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "$PLIST"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"
fi

codesign --force --deep --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run it with: open $APP"
