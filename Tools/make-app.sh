#!/usr/bin/env bash
# Assemble .build/SwiftStar.app from the release build + committed icon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
APP=.build/SwiftStar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SwiftStar "$APP/Contents/MacOS/SwiftStar"
cp Sources/SwiftStar/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SwiftStar</string>
    <key>CFBundleDisplayName</key><string>SwiftStar</string>
    <key>CFBundleIdentifier</key><string>com.pauleveritt.SwiftStar</string>
    <key>CFBundleExecutable</key><string>SwiftStar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST
echo "Wrote $APP"
