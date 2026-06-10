#!/bin/zsh
# 빌드 → pkg 생성 → GitHub Release 업로드 한번에
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.1.0}"
echo "🚀 PortSearcher v$VERSION 릴리즈 빌드"
echo ""

# ────────────────────────────────────────
# 1. CLI 빌드 & pkg
# ────────────────────────────────────────
echo "1/4 CLI 빌드..."
swift build -c release -q

rm -rf /tmp/pts-pkg
mkdir -p /tmp/pts-pkg/usr/local/bin
cp .build/release/PortSearcherCLI /tmp/pts-pkg/usr/local/bin/pts

mkdir -p dist

pkgbuild \
  --root /tmp/pts-pkg \
  --identifier kr.imjemin.pts \
  --version "$VERSION" \
  --install-location / \
  "dist/pts-$VERSION.pkg" 2>/dev/null

echo "   ✅ dist/pts-$VERSION.pkg"

# Homebrew용 바이너리 tarball 생성
rm -rf /tmp/pts-release && mkdir -p /tmp/pts-release
cp .build/release/PortSearcherCLI /tmp/pts-release/pts
cd /tmp/pts-release && tar -czf pts-arm64.tar.gz pts && cd -
cp /tmp/pts-release/pts-arm64.tar.gz "dist/pts-arm64.tar.gz"
SHA=$(shasum -a 256 dist/pts-arm64.tar.gz | awk '{print $1}')
echo "   ✅ pts-arm64.tar.gz (SHA256: $SHA)"

# ────────────────────────────────────────
# 2. GUI 앱 빌드 & pkg
# ────────────────────────────────────────
echo "2/4 GUI 앱 빌드..."
sed -i '' "s/VERSION=\".*\"/VERSION=\"$VERSION\"/" build-app.sh
# UpdateChecker 버전 자동 갱신
sed -i '' "s/currentVersion = \".*\"/currentVersion = \"$VERSION\"/" \
  PortSearcherApp/PortSearcherApp/UpdateChecker.swift \
  Sources/PortSearcherCore/UpdateChecker.swift
./build-app.sh 2>/dev/null

# rsync로 ._ AppleDouble 파일 완전 제외 후 복사
rm -rf /tmp/portsearcher-app
mkdir -p /tmp/portsearcher-app/Applications
rsync -a --exclude='._*' --exclude='.DS_Store' PortSearcher.app/ /tmp/portsearcher-app/Applications/PortSearcher.app/

# 임시 서명 (Apple Developer 인증서 없을 때 ad-hoc)
codesign --deep --force --sign - /tmp/portsearcher-app/Applications/PortSearcher.app 2>/dev/null || true

# 컴포넌트 plist 생성 후 BundleIsRelocatable=false 로 강제
#  → installer가 기존 앱을 찾아 다른 위치에 덮어쓰는 relocation 방지
pkgbuild --analyze --root /tmp/portsearcher-app /tmp/ps-component.plist 2>/dev/null
plutil -replace BundleIsRelocatable -bool false /tmp/ps-component.plist 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" /tmp/ps-component.plist

pkgbuild \
  --root /tmp/portsearcher-app \
  --component-plist /tmp/ps-component.plist \
  --identifier kr.imjemin.PortSearcherApp \
  --version "$VERSION" \
  --install-location / \
  "dist/PortSearcher-$VERSION.pkg" 2>/dev/null

echo "   ✅ dist/PortSearcher-$VERSION.pkg"

# ────────────────────────────────────────
# 3. git 태그
# ────────────────────────────────────────
echo "3/4 git 태그 생성..."
git add -A
git diff --staged --quiet || git commit -m "release: v$VERSION"
git tag -f "v$VERSION"
git push origin main --tags

echo "   ✅ v$VERSION 태그 푸시 완료"

# ────────────────────────────────────────
# 4. GitHub Release
# ────────────────────────────────────────
echo "4/4 GitHub Release 생성..."

gh release create "v$VERSION" \
  "dist/pts-$VERSION.pkg" \
  "dist/PortSearcher-$VERSION.pkg" \
  "dist/pts-arm64.tar.gz" \
  --title "v$VERSION" \
  --notes "## 설치 방법

### Homebrew (CLI)
\`\`\`bash
brew install --HEAD https://raw.githubusercontent.com/gunobo/homebrew-tap/main/Formula/pts.rb
\`\`\`

### pkg 직접 설치
\`\`\`bash
sudo installer -pkg pts-$VERSION.pkg -target /
\`\`\`
또는 pkg 파일 다운로드 후 더블클릭

| 파일 | 설명 |
|------|------|
| \`pts-$VERSION.pkg\` | 터미널 CLI 도구 (\`pts\` 명령어) |
| \`PortSearcher-$VERSION.pkg\` | 메뉴바 앱 |

> ⚠️ 처음 실행 시: **시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'**

## CLI 사용법
\`\`\`
pts               # 사용 중인 포트 목록
pts check 8080    # 사용 가능 여부 확인
pts kill 8080     # 포트 프로세스 강제 종료
pts 3000          # 단축 명령
\`\`\`" 2>&1

# ────────────────────────────────────────
# 5. Homebrew Formula 자동 갱신
# ────────────────────────────────────────
echo "5/5 Homebrew Formula 업데이트..."

TAP_DIR="/tmp/homebrew-tap-release"
rm -rf "$TAP_DIR"
git clone https://github.com/gunobo/homebrew-tap.git "$TAP_DIR" -q

SHA=$(shasum -a 256 dist/pts-arm64.tar.gz | awk '{print $1}')
sed -i '' \
  -e "s|url \".*\"|url \"https://github.com/gunobo/PortSearcher/releases/download/v$VERSION/pts-arm64.tar.gz\"|" \
  -e "s|sha256 \".*\"|sha256 \"$SHA\"|" \
  -e "s|version \".*\"|version \"$VERSION\"|" \
  "$TAP_DIR/Formula/pts.rb"

cd "$TAP_DIR"
git add Formula/pts.rb
git commit -m "update pts to v$VERSION" -q
git push -q
cd -

echo "   ✅ homebrew-tap Formula 업데이트 완료"

echo ""
echo "🎉 완료! https://github.com/gunobo/PortSearcher/releases/tag/v$VERSION"
