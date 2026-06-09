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

pkgbuild \
  --root /tmp/pts-pkg \
  --identifier kr.imjemin.pts \
  --version "$VERSION" \
  --install-location / \
  "pts-$VERSION.pkg" 2>/dev/null

echo "   ✅ pts-$VERSION.pkg"

# Homebrew용 바이너리 tarball 생성
rm -rf /tmp/pts-release && mkdir -p /tmp/pts-release
cp .build/release/PortSearcherCLI /tmp/pts-release/pts
cd /tmp/pts-release && tar -czf pts-arm64.tar.gz pts && cd -
cp /tmp/pts-release/pts-arm64.tar.gz "pts-arm64.tar.gz"
SHA=$(shasum -a 256 pts-arm64.tar.gz | awk '{print $1}')
echo "   ✅ pts-arm64.tar.gz (SHA256: $SHA)"

# ────────────────────────────────────────
# 2. GUI 앱 빌드 & pkg
# ────────────────────────────────────────
echo "2/4 GUI 앱 빌드..."
./build-app.sh 2>/dev/null

rm -rf /tmp/portsearcher-app
mkdir -p /tmp/portsearcher-app/Applications
cp -R PortSearcher.app /tmp/portsearcher-app/Applications/

pkgbuild \
  --root /tmp/portsearcher-app \
  --identifier kr.imjemin.PortSearcherApp \
  --version "$VERSION" \
  --install-location / \
  "PortSearcher-$VERSION.pkg" 2>/dev/null

echo "   ✅ PortSearcher-$VERSION.pkg"

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
  "pts-$VERSION.pkg" \
  "PortSearcher-$VERSION.pkg" \
  "pts-arm64.tar.gz" \
  --title "v$VERSION" \
  --notes "## 설치 방법

pkg 파일 다운로드 후 더블클릭으로 설치

| 파일 | 설명 |
|------|------|
| \`pts-$VERSION.pkg\` | 터미널 CLI 도구 (\`pts\` 명령어) |
| \`PortSearcher-$VERSION.pkg\` | 메뉴바 앱 |

> ⚠️ 처음 실행 시: **시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'**

## CLI 사용법
\`\`\`
pts               # 사용 중인 포트 목록
pts check 8080    # 사용 가능 여부 확인
pts 3000          # 단축 명령
\`\`\`" 2>&1

echo ""
echo "🎉 완료! https://github.com/gunobo/PortSearcher/releases/tag/v$VERSION"
