#!/bin/bash
# Build PM2Desktop.app bundle (release, ad-hoc signed) into ./build/
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/PM2Desktop.app"
EXEC="PM2Desktop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/"$EXEC" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PM2 Desktop</string>
    <key>CFBundleDisplayName</key>
    <string>PM2 Desktop</string>
    <key>CFBundleIdentifier</key>
    <string>com.pm2desktop.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP"

# Assemble .dmg installer (drag PM2 Desktop onto Applications)
STAGING="build/dmg-staging"
DMG="build/PM2Desktop.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "PM2 Desktop" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Built $APP"
echo "Built $DMG"
echo "Install: open $DMG → drag PM2 Desktop into Applications"
