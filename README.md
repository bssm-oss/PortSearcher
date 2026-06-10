# PortSearcher

macOS에서 사용 중인 포트를 확인하고, 프로세스를 강제 종료할 수 있는 도구입니다.  
CLI와 메뉴바 GUI 앱 두 가지 방식으로 사용할 수 있습니다.

## 기능

- 현재 시스템에서 사용 중인 모든 TCP/UDP 포트 목록 조회
- 특정 포트 번호 입력 → 사용 가능 / 사용 중 즉시 확인
- 사용 중인 포트의 프로세스 강제 종료 (GUI · CLI)
- 포트 이름/번호/PID로 검색 (GUI)
- 새 버전 자동 감지 및 업데이트 알림

## 요구사항

- macOS 13+
- Swift 5.9+

---

## 설치

### Homebrew (CLI)

```bash
brew tap gunobo/tap
brew install pts
```

> 업데이트: `brew upgrade pts`

### pkg 직접 설치

[GitHub Releases](https://github.com/bssm-oss/PortSearcher/releases/latest)에서 pkg 파일 다운로드 후 더블클릭

| 파일 | 설명 |
|------|------|
| `pts-x.x.x.pkg` | 터미널 CLI 도구 |
| `PortSearcher-x.x.x.pkg` | 메뉴바 앱 |

> ⚠️ 처음 실행 시: **시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'**

---

## GUI 앱 (메뉴바)

상단 메뉴바 아이콘 클릭으로 사용합니다.

| 기능 | 설명 |
|------|------|
| 포트 체크 | 포트 번호 입력 후 Enter — 사용 가능 여부 즉시 확인 |
| 포트 목록 | 현재 LISTEN 중인 전체 포트 표시 |
| 강제 종료 | 포트 행에 마우스 오버 → 🔴 버튼 클릭 |
| 검색 | 프로세스명 · 포트번호 · PID로 필터 |
| 새로고침 | 버튼 클릭 시 목록 갱신 |
| 업데이트 알림 | 새 버전 출시 시 상단 배너 표시 |

---

## CLI

### 사용법

```
pts                  현재 사용 중인 포트 목록 출력
pts check <포트>     포트 사용 가능 여부 확인
pts info  <포트>     해당 포트를 점유한 프로세스 정보
pts kill  <포트>     해당 포트 프로세스 강제 종료
pts <포트번호>        (단축) 숫자만 입력해도 check 동작
pts version          현재 버전 확인
pts help             도움말
```

### 예시

```
$ pts
PORT    PID       PROTO   PROCESS
--------------------------------------------
3000    48600     TCP     node
5000    1037      TCP     ControlCe
6379    1537      TCP     redis-ser
8001    1371      TCP     com.docke

총 4개 포트 사용 중

$ pts check 8080
✅ 포트 8080: 사용 가능

$ pts check 3000
❌ 포트 3000: 사용 중
   프로세스: node (PID: 48600)

$ pts kill 3000
종료 대상: node (PID: 48600) — 포트 3000
✅ 프로세스 종료 완료
```

---

## 프로젝트 구조

```
PortSearcher/
├── Package.swift
├── install.sh                           # CLI 전역 설치 스크립트
├── build-app.sh                         # GUI 앱 빌드 스크립트
├── release.sh                           # 릴리즈 자동화 스크립트
├── dist/                                # 빌드 결과물 (pkg, tar.gz)
├── Sources/
│   ├── PortSearcherCore/
│   │   ├── PortScanner.swift            # 핵심 로직 (lsof + socket)
│   │   └── UpdateChecker.swift          # 버전 업데이트 확인
│   └── PortSearcherCLI/
│       └── main.swift                   # CLI 진입점
└── PortSearcherApp/
    └── PortSearcherApp/
        ├── PortSearcherApp.swift        # 메뉴바 앱 진입점
        ├── ContentView.swift            # 메인 UI
        ├── PortScanner.swift            # GUI용 포트 스캐너
        └── UpdateChecker.swift          # GUI용 업데이트 확인
```

## 동작 원리

- **포트 목록**: `lsof -iTCP -sTCP:LISTEN` 출력 파싱
- **사용 가능 여부**: 실제 소켓 바인딩 시도 (bind syscall)
- **강제 종료**: SIGKILL 시그널 전송
- **업데이트 확인**: GitHub Releases API 조회
