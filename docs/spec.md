# PortSearcher 기술 명세서

> 버전: 1.4.0 | 최종 수정: 2026-06-10

---

## 1. 개요

PortSearcher는 macOS에서 사용 중인 TCP/UDP 포트를 조회·분석·관리하는 도구입니다.  
동일한 핵심 로직(`PortSearcherCore`) 위에 **CLI(`pts`)** 와 **메뉴바 GUI 앱** 두 가지 인터페이스를 제공합니다.

---

## 2. 요구사항

| 항목 | 최소 사양 |
|------|-----------|
| macOS | 13 (Ventura) 이상 |
| Swift | 5.9 이상 |
| 아키텍처 | arm64 (Apple Silicon) / x86_64 (Intel) |
| 권한 | 일반 사용자 (kill은 동일 UID 프로세스만, 타 UID는 sudo 필요) |

---

## 3. 아키텍처

```
PortSearcher/
├── Package.swift                        # Swift Package Manager 설정
├── Sources/
│   ├── PortSearcherCore/                # 공유 핵심 라이브러리
│   │   ├── PortScanner.swift            # 포트 스캔 / kill 로직
│   │   └── UpdateChecker.swift          # 버전 비교 & 업데이트 확인
│   └── PortSearcherCLI/
│       └── main.swift                   # CLI 진입점 (pts)
└── PortSearcherApp/
    └── PortSearcherApp/
        ├── PortSearcherApp.swift        # NSApplicationDelegate, 메뉴바 StatusItem
        ├── ContentView.swift            # SwiftUI 뷰 계층 + PortViewModel
        ├── PortScanner.swift            # GUI 전용 PortScanner (async 래퍼)
        └── UpdateChecker.swift          # GUI 전용 UpdateChecker (자동 설치 포함)
```

### 3.1 모듈 의존성

```
PortSearcherCLI ──depends──▶ PortSearcherCore
PortSearcherApp  ──(자체 복사본 유지)
```

> GUI 앱은 SPM 타깃과 분리된 Xcode 프로젝트로 관리되므로 Core 소스를 별도 복사해 사용합니다.

---

## 4. 데이터 모델

### 4.1 `PortInfo`

```swift
public struct PortInfo: Identifiable, Sendable {
    public let id: UUID          // 목록 식별자 (뷰 바인딩용)
    public let port: UInt16      // 포트 번호 (1–65535)
    public let pid: Int32        // 프로세스 ID
    public let processName: String  // 전체 프로세스 이름 (ps -o comm= 결과)
    public let proto: String     // 프로토콜 문자열 ("TCP" 등)
    public let uptime: String    // 사람이 읽기 좋은 업타임 ("3h 12m" 형식)
}
```

---

## 5. 핵심 로직 (`PortSearcherCore`)

### 5.1 `PortScanner`

#### `activePorts() -> [PortInfo]`

| 단계 | 설명 |
|------|------|
| 1. lsof 실행 | `/usr/sbin/lsof -iTCP -iUDP -n -P -sTCP:LISTEN` 실행 |
| 2. 파싱 | 공백 분리 후 PID(col 2), 프로토콜(col 8), 주소:포트(col 9) 추출 |
| 3. 포트 파싱 | `addressField.split(":").last` — `*.8080`, `127.0.0.1:8080`, `[::]:8080` 모두 처리 |
| 4. 중복 제거 | (port, pid) 쌍이 동일하면 스킵 |
| 5. 프로세스 정보 | `ps -ww -p <pid> -o comm=` 으로 전체 경로명 취득 후 `lastPathComponent` 추출 |
| 6. 업타임 | `ps -ww -p <pid> -o etime=` 결과를 `formatEtime()` 으로 변환 |
| 7. 정렬 | 포트 번호 오름차순 |

**업타임 포맷 규칙 (`formatEtime`)**

| ps etime 형식 | 변환 결과 예시 |
|---------------|----------------|
| `DD-HH:MM:SS` | `3d 2h` |
| `HH:MM:SS`    | `5h 30m` |
| `MM:SS`       | `12m 4s` |
| `SS`          | `45s` |

#### `isPortAvailable(_ port: UInt16) -> Bool`

TCP 소켓을 직접 생성하고 `bind(2)` 시스템 콜을 시도합니다.  
`SO_REUSEADDR` 옵션을 활성화한 뒤 `INADDR_ANY`에 바인딩을 시도하며, 반환값 `0` 이면 사용 가능으로 판단합니다.

#### `processUsing(port: UInt16) -> PortInfo?`

`activePorts()` 결과에서 일치하는 포트를 선형 탐색합니다.

#### `killProcess(pid: Int32) -> (Bool, String?)`

`kill(pid, SIGKILL)` 시스템 콜을 발행합니다.

| errno | 반환 메시지 |
|-------|-------------|
| `EPERM` | `"권한 없음 — sudo 필요"` |
| `ESRCH` | `"프로세스가 이미 종료됨"` |
| 기타 | `strerror(errno)` |

---

### 5.2 `UpdateChecker` (Core)

- **현재 버전**: 소스 내 상수 `currentVersion = "1.4.0"`
- **API**: `GET https://api.github.com/repos/bssm-oss/PortSearcher/releases/latest`  
  `Accept: application/vnd.github+json`, 타임아웃 5초
- **버전 비교**: `tag_name`의 `v` 접두사를 제거한 뒤 `.` 분리 숫자 배열로 비교  
  → 최신 버전이 현재보다 높을 때만 `String` 반환, 그렇지 않으면 `nil`
- **동기 호출**: `DispatchSemaphore`로 URLSession 비동기 태스크를 차단하여 동기처럼 사용

---

## 6. CLI 명세 (`pts`)

### 6.1 명령어 목록

| 명령어 | 동작 |
|--------|------|
| `pts` / `pts list` | 현재 LISTEN 포트 테이블 출력 |
| `pts check <포트>` | 포트 사용 가능 여부 확인 |
| `pts info <포트>` | 해당 포트의 프로세스 정보 표시 |
| `pts kill <포트>` | 해당 포트 프로세스에 SIGKILL |
| `pts <숫자>` | `check` 단축 (숫자 단독 입력) |
| `pts version` / `--version` / `-v` | 버전 출력 |
| `pts help` / `--help` / `-h` | 도움말 출력 |

### 6.2 출력 형식 (`list`)

```
PORT    PID       PROTO   UPTIME    PROCESS
------------------------------------------------------
3000    48600     TCP     12m 4s    node
8080    1234      TCP     3h 20m    nginx
```

컬럼 너비: PORT 8, PID 10, PROTO 8, UPTIME 10, PROCESS 가변

### 6.3 종료 코드

| 상황 | 코드 |
|------|------|
| 정상 | `0` |
| 잘못된 포트 번호 | `1` |
| kill 실패 | `1` |
| 알 수 없는 명령어 | `1` |

### 6.4 업데이트 알림 (CLI)

모든 명령 실행 시 `updateQueue`에서 백그라운드로 업데이트를 확인합니다.  
메인 로직 완료 후 `updateSema.wait()`으로 결과를 수집하여 새 버전이 있을 경우 stdout에 출력합니다.

---

## 7. GUI 앱 명세

### 7.1 진입점 및 생명주기

- `@main struct PortSearcherApp`: SwiftUI App 래퍼 (Settings scene만 보유)
- `AppDelegate.applicationDidFinishLaunching`:
  - `NSApp.setActivationPolicy(.accessory)` — Dock 미표시
  - `NSStatusBar.system.statusItem` — 메뉴바 아이콘(`network` SF Symbol) 등록
  - `NSPopover` (420×520 pt, `.transient` 동작) 생성 후 `MenuBarView` 삽입

### 7.2 뷰 계층

```
MenuBarView
├── TopBar          (제목, 포트 수, 새로고침 버튼)
├── UpdateBanner?   (새 버전 있을 때만 표시)
├── CheckPanel      (포트 번호 입력 → 즉시 확인)
│   └── CheckResultBadge
├── PortList        (검색 필터 + 컬럼 헤더 + ScrollView)
│   └── PortRow × N  (hover 시 kill 버튼 표시)
└── BottomBar       (앱 종료 버튼)
```

### 7.3 `PortViewModel` (ObservableObject)

| 상태 프로퍼티 | 타입 | 설명 |
|---------------|------|------|
| `activePorts` | `[PortInfo]` | 전체 포트 목록 |
| `filteredPorts` | 계산 프로퍼티 | `searchText` 기반 필터 결과 |
| `checkInput` | `String` | 포트 입력 필드 값 |
| `checkResult` | `CheckResult?` | `.available` / `.inUse` / `.invalid` |
| `isLoading` | `Bool` | 새로고침 중 스피너 표시 |
| `searchText` | `String` | 포트/프로세스명/PID 검색 필터 |
| `latestVersion` | `String?` | 새 버전 번호 (없으면 nil) |
| `updateState` | `UpdateState` | `.idle` / `.downloading(progress)` / `.ready` / `.failed(msg)` |

#### 검색 필터 조건

```
port 문자열 포함 OR 프로세스명 대소문자 무시 포함 OR PID 문자열 포함
```

### 7.4 UpdateBanner 상태 머신

```
idle ──[자동 업데이트 클릭]──▶ downloading(0.0..1.0)
                                     │
                               [완료]─▶ ready ──[앱 자동 종료 후 재실행]
                                     │
                              [오류]─▶ failed(msg) ──[재시도]──▶ downloading
idle / failed ──[✕ 클릭]──▶ (배너 제거)
```

### 7.5 GUI용 `UpdateChecker` 추가 기능

Core의 `UpdateChecker`와 달리 GUI 버전은 아래를 추가로 제공합니다.

| 메서드 | 설명 |
|--------|------|
| `fetchLatestVersion(completion:)` | 비동기 콜백 버전 |
| `downloadAndInstall(version:progress:)` | pkg 다운로드 → 설치 → 앱 재실행 자동화 |

---

## 8. 빌드 & 배포

### 8.1 CLI 빌드

```bash
swift build -c release
# 결과물: .build/release/PortSearcherCLI
```

### 8.2 앱 빌드

```bash
./build-app.sh
# Xcode 아카이브 → PortSearcher.app → PortSearcher-x.x.x.pkg 생성
```

### 8.3 릴리즈 자동화

```bash
./release.sh
# 1. swift build (CLI)
# 2. build-app.sh (GUI)
# 3. pkg 패키징 → dist/
# 4. git tag & GitHub Release 생성
```

### 8.4 패키지 구성

| 파일 | 설명 |
|------|------|
| `pts-x.x.x.pkg` | CLI 도구 (`/usr/local/bin/pts` 설치) |
| `PortSearcher-x.x.x.pkg` | 메뉴바 앱 (`/Applications/PortSearcher.app`) |
| `pts-arm64.tar.gz` | arm64 바이너리 단독 압축 |

---

## 9. 주요 제약 및 알려진 동작

| 항목 | 내용 |
|------|------|
| LISTEN 포트만 표시 | `lsof -sTCP:LISTEN` 필터 적용 — ESTABLISHED 연결은 표시 안 됨 |
| UDP 조회 | 인수에 `-iUDP` 포함하나, `LISTEN` 필터로 실질적으로 TCP만 표시 |
| 타 UID kill | `EPERM` 반환 → 사용자에게 sudo 안내 메시지 출력 |
| 업타임 정밀도 | `ps etime` 기준 — 1초 미만 오차 가능 |
| 업데이트 확인 | 네트워크 없을 시 5초 타임아웃 후 조용히 스킵 |
