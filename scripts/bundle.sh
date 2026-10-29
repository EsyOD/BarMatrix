#!/bin/sh
# 编译并打包成 BarMatrix.app（放在 build/ 下）
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/BarMatrix.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BarMatrix "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BarMatrix</string>
  <key>CFBundleIdentifier</key><string>com.barmatrix.app</string>
  <key>CFBundleExecutable</key><string>BarMatrix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "已生成 $APP"
