#!/bin/zsh
# Xcode 없이 SwiftUI 메뉴바 앱 번들 직접 빌드
set -e
cd "$(dirname "$0")"

APP_NAME="PortSearcher"
BUNDLE="$APP_NAME.app"
VERSION="1.1.0"
BUNDLE_ID="kr.imjemin.PortSearcherApp"

SRC=(
  "PortSearcherApp/PortSearcherApp/PortScanner.swift"
  "PortSearcherApp/PortSearcherApp/ContentView.swift"
  "PortSearcherApp/PortSearcherApp/PortSearcherApp.swift"
)

echo "🔨 컴파일 중..."

# 번들 구조 생성
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# 컴파일
swiftc -O \
  -sdk $(xcrun --show-sdk-path) \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  "${SRC[@]}" \
  -o "$BUNDLE/Contents/MacOS/$APP_NAME"

echo "📦 Info.plist 생성..."
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>PortSearcher</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "🖼️  아이콘 복사..."
if [ -f "logo/AppIcon.icns" ]; then
  cp "logo/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
  echo "   ✅ AppIcon.icns 적용"
fi

echo "✅ 빌드 완료: $BUNDLE"
echo ""
echo "실행: open $BUNDLE"
