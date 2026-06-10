#!/bin/zsh
# CLI 설치: /usr/local/bin/pts 로 복사

set -e
cd "$(dirname "$0")"

echo "빌드 중..."
swift build -c release

DEST="/usr/local/bin/pts"
echo "설치 중: $DEST"
sudo cp .build/release/PortSearcherCLI "$DEST"
sudo chmod +x "$DEST"

echo "✅ 설치 완료!"
echo ""
echo "사용법:"
echo "  pts               # 사용 중인 포트 목록"
echo "  pts check 8080    # 포트 사용 가능 여부"
echo "  pts info 6379     # 포트 사용 프로세스 정보"
echo "  pts 3000          # (단축) 포트 번호만 입력"
