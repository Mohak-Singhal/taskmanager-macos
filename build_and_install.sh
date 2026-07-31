#!/bin/bash
set -e

echo "=== Step 1: Compiling Task Manager in Release Mode ==="
swift build -c release

echo "=== Step 2: Generating Apple .icns Icon file ==="
ICON_PNG="Resources/AppIcon.png"
ICONSET="Resources/AppIcon.iconset"

mkdir -p "$ICONSET"
sips -s format png -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" > /dev/null

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"

echo "=== Step 3: Assembling macOS App Bundle ==="
APP_DIR="TaskManagerNative.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/TaskManagerNative "$APP_DIR/Contents/MacOS/TaskManagerNative"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Write Info.plist
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TaskManagerNative</string>
    <key>CFBundleIdentifier</key>
    <string>com.taskmanager.native</string>
    <key>CFBundleName</key>
    <string>TaskManagerNative</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "=== Step 4: Installing to /Applications ==="
DEST_APP="/Applications/TaskManagerNative.app"
if [ -d "$DEST_APP" ]; then
    echo "Removing existing installation..."
    rm -rf "$DEST_APP"
fi

cp -R "$APP_DIR" "/Applications/"
rm -rf "$APP_DIR"

echo "=== Step 5: Codesigning with Entitlements ==="
codesign --force --entitlements TaskManagerNative.entitlements -s - "$DEST_APP/Contents/MacOS/TaskManagerNative"
codesign --force --entitlements TaskManagerNative.entitlements -s - "$DEST_APP"

echo "=== SUCCESS: Task Manager installed in /Applications! ==="
