# PortSearcher

> macOS 메뉴바 & CLI에서 포트를 즉시 조회·관리하는 도구

[![Version](https://img.shields.io/badge/version-1.4.0-blue)](https://github.com/bssm-oss/PortSearcher/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/bssm-oss/PortSearcher)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 기능

| 기능 | CLI | GUI |
|------|:---:|:---:|
| LISTEN 포트 전체 목록 조회 | ✅ | ✅ |
| 특정 포트 사용 가능 여부 즉시 확인 | ✅ | ✅ |
| 포트를 점유한 프로세스 정보 (PID, 이름, 업타임) | ✅ | ✅ |
| 프로세스 강제 종료 (SIGKILL) | ✅ | ✅ |
| 포트·프로세스명·PID로 실시간 검색 | ❌ | ✅ |
| 새 버전 자동 감지 & 업데이트 알림 | ✅ | ✅ |
| 원클릭 자동 업데이트 | ❌ | ✅ |

---

## 설치

### Homebrew (CLI)

```bash
brew tap gunobo/tap
brew install pts
```

업데이트:
```bash
brew upgrade pts
```

### pkg 직접 설치

[GitHub Releases](https://github.com/bssm-oss/PortSearcher/releases/latest)에서 다운로드

| 파일 | 설명 |
|------|------|
| `pts-x.x.x.pkg` | 터미널 CLI 도구 (`pts` 커맨드) |
| `PortSearcher-x.x.x.pkg` | 메뉴바 GUI 앱 |

> **처음 실행 시**: 시스템 설정 → 개인정보 보호 및 보안 → **'확인 없이 열기'** 선택

---

## CLI 사용법

```
pts                    현재 사용 중인 포트 목록 출력
pts check <포트번호>   포트 사용 가능 여부 확인
pts info  <포트번호>   해당 포트를 점유한 프로세스 정보
pts kill  <포트번호>   해당 포트 프로세스 강제 종료
pts <포트번호>          숫자만 입력해도 check 동작
pts version            현재 버전 확인
pts help               도움말
```

### 예시

```
$ pts
PORT    PID       PROTO   UPTIME    PROCESS
------------------------------------------------------
3000    48600     TCP     12m 4s    node
5432    1234      TCP     3h 20m    postgres
6379    1537      TCP     2d 5h     redis-server
8080    9921      TCP     45s       python3

총 4개 포트 사용 중

$ pts check 8080
❌ 포트 8080: 사용 중
   프로세스: python3 (PID: 9921)

$ pts check 9000
✅ 포트 9000: 사용 가능

$ pts kill 3000
종료 대상: node (PID: 48600) — 포트 3000
✅ 프로세스 종료 완료
```

---

## GUI 앱 (메뉴바)

메뉴바 아이콘(🌐)을 클릭하면 팝업이 열립니다.

| 기능 | 사용 방법 |
|------|-----------|
| 포트 확인 | 상단 입력창에 포트 번호 입력 후 Enter |
| 포트 목록 | 팝업 하단 스크롤 목록에서 확인 |
| 프로세스 종료 | 포트 행에 마우스 오버 → 🔴 버튼 클릭 |
| 검색 | 검색창에 포트번호·프로세스명·PID 입력 |
| 새로고침 | 우측 상단 ↻ 버튼 클릭 |
| 자동 업데이트 | 새 버전 배너에서 '자동 업데이트' 버튼 클릭 |

---

## 프로젝트 구조

```
PortSearcher/
├── Package.swift
├── Sources/
│   ├── PortSearcherCore/
│   │   ├── PortScanner.swift       # 핵심 로직 (lsof 파싱, socket bind, SIGKILL)
│   │   └── UpdateChecker.swift     # GitHub Releases API 버전 비교
│   └── PortSearcherCLI/
│       └── main.swift              # CLI 진입점 (pts)
├── PortSearcherApp/
│   └── PortSearcherApp/
│       ├── PortSearcherApp.swift   # 메뉴바 StatusItem & Popover
│       ├── ContentView.swift       # SwiftUI 뷰 + PortViewModel
│       ├── PortScanner.swift       # GUI용 PortScanner
│       └── UpdateChecker.swift     # GUI용 UpdateChecker (자동 설치 포함)
├── dist/                           # 빌드 결과물 (pkg, tar.gz)
├── docs/
│   └── spec.md                     # 기술 명세서
├── build-app.sh                    # GUI 앱 빌드
├── install.sh                      # CLI 전역 설치
└── release.sh                      # 릴리즈 자동화
```

---

## 동작 원리

| 기능 | 구현 방식 |
|------|-----------|
| 포트 목록 | `lsof -iTCP -sTCP:LISTEN` 출력 파싱 |
| 프로세스 이름·업타임 | `ps -ww -p <pid> -o comm=,etime=` |
| 포트 가용 여부 | 실제 TCP 소켓 `bind(2)` 시도 |
| 프로세스 종료 | `kill(pid, SIGKILL)` 시스템 콜 |
| 업데이트 확인 | GitHub Releases API (타임아웃 5초) |

---

## 직접 빌드

```bash
# CLI
swift build -c release
sudo cp .build/release/PortSearcherCLI /usr/local/bin/pts

# GUI 앱
./build-app.sh
```

---

## 기술 명세

자세한 아키텍처·데이터 모델·API 명세는 [docs/spec.md](docs/spec.md)를 참고하세요.

---

## 요구사항

| 환경 | CLI (`pts`) | GUI 메뉴바 앱 |
|------|:-----------:|:------------:|
| macOS 13+ | ✅ | ✅ |
| Linux (Ubuntu / Raspberry Pi) | ✅ | ❌ |

- Swift 5.9+
- Linux: `sudo apt install lsof` 필요

### Linux / Raspberry Pi 설치

```bash
# Swift 설치 (swift.org 참고)
# 소스 빌드
git clone https://github.com/bssm-oss/PortSearcher.git
cd PortSearcher
swift build -c release
sudo cp .build/release/PortSearcherCLI /usr/local/bin/pts
```

---

## 라이선스

[MIT](LICENSE)
