#!/bin/sh
# 编译并打包成 BarMatrix.app（放在 build/ 下）
set -e
cd "$(dirname "$0")/.."
# UNIVERSAL=1 同时编译 Apple 芯片和 Intel 版本（CI 发布时使用）
if [ "$UNIVERSAL" = "1" ]; then
  ARCHS="--arch arm64 --arch x86_64"
fi
VERSION="${VERSION:-0.1.0}"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/BarMatrix"
APP=build/BarMatrix.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"

# 由 Resources/AppIcon.png 生成 AppIcon.icns
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BarMatrix</string>
  <key>CFBundleIdentifier</key><string>com.barmatrix.app</string>
  <key>CFBundleExecutable</key><string>BarMatrix</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "已生成 $APP"
