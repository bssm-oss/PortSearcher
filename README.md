# PortSearcher

macOS에서 사용 중인 포트를 확인하고, 특정 포트의 사용 가능 여부를 체크하는 도구입니다.  
CLI와 SwiftUI GUI 앱 두 가지 방식으로 사용할 수 있습니다.

## 기능

- 현재 시스템에서 사용 중인 모든 TCP 포트 목록 조회
- 특정 포트 번호 입력 → 사용 가능 / 사용 중 즉시 확인
- 사용 중인 포트의 프로세스 이름 및 PID 표시
- 포트 이름/번호/PID로 검색 (GUI)

## 요구사항

- macOS 13+
- Xcode 15+ 또는 Swift 5.9+

---

## GUI 앱

`PortSearcherApp/PortSearcherApp.xcodeproj`를 Xcode에서 열고 ▶ 실행합니다.

| 기능 | 설명 |
|------|------|
| 포트 체크 패널 | 포트 번호 입력 후 Enter 또는 확인 버튼 |
| 포트 목록 | 현재 LISTEN 중인 포트 전체 목록 |
| 검색 | 프로세스명, 포트번호, PID로 필터 |
| 새로고침 | 버튼 클릭 시 목록 갱신 |
| 행 클릭 | 해당 포트를 체크 패널에 자동 입력 |

---

## CLI

### 빌드 및 실행

```bash
# 바로 실행 (빌드 포함)
swift run PortSearcherCLI
swift run PortSearcherCLI check 8080
swift run PortSearcherCLI info 3000
```

### 전역 설치

```bash
./install.sh
```

설치 후 어디서든 `pts` 명령으로 사용 가능합니다.

### 사용법

```
pts                  현재 사용 중인 포트 목록 출력
pts check <포트>     포트 사용 가능 여부 확인
pts info  <포트>     해당 포트를 점유한 프로세스 정보
pts <포트번호>        (단축) 숫자만 입력해도 check 동작
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

총 33개 포트 사용 중

$ pts check 8080
✅ 포트 8080: 사용 가능

$ pts check 3000
❌ 포트 3000: 사용 중
   프로세스: node (PID: 48600)

$ pts info 6379
포트 6379 정보:
  프로세스: redis-ser
  PID:     1537
  프로토콜: TCP
```

---

## 프로젝트 구조

```
PortSearcher/
├── Package.swift                        # Swift Package (CLI)
├── install.sh                           # CLI 전역 설치 스크립트
├── Sources/
│   ├── PortSearcherCore/
│   │   └── PortScanner.swift            # 핵심 로직 (lsof + socket)
│   └── PortSearcherCLI/
│       └── main.swift                   # CLI 진입점
└── PortSearcherApp/
    ├── PortSearcherApp.xcodeproj/
    └── PortSearcherApp/
        ├── PortSearcherApp.swift        # SwiftUI @main
        ├── ContentView.swift            # 메인 UI
        └── PortScanner.swift            # GUI용 포트 스캐너
```

## 동작 원리

- **포트 목록**: `lsof -iTCP -sTCP:LISTEN` 출력 파싱
- **사용 가능 여부**: 실제 소켓 바인딩 시도 (bind syscall)
