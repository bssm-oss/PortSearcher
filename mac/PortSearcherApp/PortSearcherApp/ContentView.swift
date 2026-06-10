import SwiftUI
import AppKit

// MARK: - ViewModel

@MainActor
class PortViewModel: ObservableObject {
    @Published var activePorts: [PortInfo] = []
    @Published var checkInput: String = ""
    @Published var checkResult: CheckResult? = nil
    @Published var isLoading = false
    @Published var searchText: String = ""
    @Published var latestVersion: String? = nil
    @Published var updateState: UpdateState = .idle

    private let scanner = PortScanner()
    private let updater = UpdateChecker()

    enum CheckResult: Equatable {
        case available(UInt16)
        case inUse(UInt16, String, Int32)   // port, processName, pid
        case invalid
    }

    var filteredPorts: [PortInfo] {
        guard !searchText.isEmpty else { return activePorts }
        return activePorts.filter {
            "\($0.port)".contains(searchText) ||
            $0.processName.localizedCaseInsensitiveContains(searchText) ||
            "\($0.pid)".contains(searchText)
        }
    }

    func refresh() {
        isLoading = true
        Task.detached(priority: .userInitiated) { [scanner] in
            let ports = scanner.activePorts()
            await MainActor.run {
                self.activePorts = ports
                self.isLoading = false
            }
        }
    }

    func checkForUpdate() {
        updater.fetchLatestVersion { [weak self] version in
            DispatchQueue.main.async {
                self?.latestVersion = version
            }
        }
    }

    func startUpdate() {
        guard let version = latestVersion else { return }
        updater.downloadAndInstall(version: version) { [weak self] state in
            self?.updateState = state
        }
    }

    func killPort(_ info: PortInfo) {
        let alert = NSAlert()
        alert.messageText = "포트 \(info.port) 프로세스를 종료할까요?"
        alert.informativeText = "\(info.processName) (PID: \(info.pid))를 강제 종료합니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let (success, errMsg) = scanner.killProcess(pid: info.pid)
        if success {
            // 잠깐 대기 후 새로고침 (프로세스 종료 반영)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.refresh()
            }
        } else {
            let err = NSAlert()
            err.messageText = "종료 실패"
            err.informativeText = errMsg ?? "알 수 없는 오류"
            err.alertStyle = .critical
            err.runModal()
        }
    }

    func checkPort() {
        let raw = checkInput.trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(raw), port > 0 else {
            checkResult = .invalid
            return
        }
        Task.detached(priority: .userInitiated) { [scanner] in
            let available = scanner.isPortAvailable(port)
            let info = scanner.processUsing(port: port)
            await MainActor.run {
                if available {
                    self.checkResult = .available(port)
                } else {
                    self.checkResult = .inUse(port, info?.processName ?? "알 수 없음", info?.pid ?? 0)
                }
            }
        }
    }
}

// MARK: - MenuBar Root View

struct MenuBarView: View {
    @StateObject private var vm = PortViewModel()

    var body: some View {
        VStack(spacing: 0) {
            TopBar(vm: vm)
            if let latest = vm.latestVersion {
                UpdateBanner(latestVersion: latest, state: vm.updateState,
                             onUpdate: { vm.startUpdate() },
                             onDismiss: { vm.latestVersion = nil; vm.updateState = .idle })
            }
            Divider()
            CheckPanel(vm: vm)
            Divider()
            PortList(vm: vm)
            Divider()
            BottomBar()
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            vm.refresh()
            vm.checkForUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
            vm.refresh()
            vm.checkForUpdate()
        }
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @ObservedObject var vm: PortViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            Text("PortSearcher")
                .font(.system(size: 13, weight: .semibold))
            if vm.isLoading {
                ProgressView().scaleEffect(0.55)
            } else {
                Text("\(vm.activePorts.count)개 사용 중")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                vm.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
            .help("새로고침")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Check Panel

struct CheckPanel: View {
    @ObservedObject var vm: PortViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("포트 번호 입력 후 Enter", text: $vm.checkInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($focused)
                    .onSubmit { vm.checkPort() }
                if !vm.checkInput.isEmpty {
                    Button {
                        vm.checkInput = ""
                        vm.checkResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button("확인") { vm.checkPort() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(vm.checkInput.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

            if let result = vm.checkResult {
                CheckResultBadge(result: result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: vm.checkResult)
    }
}

struct CheckResultBadge: View {
    let result: PortViewModel.CheckResult

    var body: some View {
        HStack(spacing: 6) {
            switch result {
            case .available(let port):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("포트 \(String(port)) — 사용 가능").foregroundStyle(.green)
                    .font(.system(size: 12, weight: .medium))
            case .inUse(let port, let name, let pid):
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("포트 \(String(port)) — 사용 중").foregroundStyle(.red)
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text("\(name)  ·  PID \(String(pid))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            case .invalid:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("1–65535 사이 숫자를 입력하세요").foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(badgeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    var badgeColor: Color {
        switch result {
        case .available: .green
        case .inUse:     .red
        case .invalid:   .orange
        }
    }
}

// MARK: - Port List

struct PortList: View {
    @ObservedObject var vm: PortViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 검색 + 컬럼 헤더
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("검색", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Divider()

            HStack {
                Text("PORT").frame(width: 52, alignment: .leading)
                Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 60, alignment: .trailing)
                Text("PROTO").frame(width: 48, alignment: .trailing)
                Text("UPTIME").frame(width: 52, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if vm.filteredPorts.isEmpty && !vm.isLoading {
                Spacer()
                Text(vm.searchText.isEmpty ? "사용 중인 포트 없음" : "검색 결과 없음")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredPorts) { info in
                            PortRow(info: info, onKill: { vm.killPort(info) })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    vm.checkInput = "\(info.port)"
                                    vm.checkResult = .inUse(info.port, info.processName, info.pid)
                                }
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct PortRow: View {
    let info: PortInfo
    let onKill: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(String(info.port))
                .font(.system(size: 13, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .leading)

            Text(info.processName)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(info.pid))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(info.proto)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .frame(width: 48, alignment: .trailing)

            if !info.uptime.isEmpty {
                Text(info.uptime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }

            // 강제 종료 버튼 (hover 시 표시)
            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .opacity(hovered ? 1 : 0)
            .help("프로세스 강제 종료")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let latestVersion: String
    let state: UpdateState
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)

            switch state {
            case .idle:
                Text("새 버전 v\(latestVersion) 출시!")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("자동 업데이트") { onUpdate() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 3) {
                    Text("다운로드 중... \(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    ProgressView(value: progress)
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                }
                Spacer()

            case .ready:
                Text("설치 중... 잠시 후 앱이 종료됩니다")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()

            case .failed(let msg):
                Text("실패: \(msg)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                Spacer()
                Button("재시도") { onUpdate() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }

            if state == .idle || isFailed {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isFailed ? Color.red : Color.accentColor)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    var body: some View {
        HStack {
            Spacer()
            Button("종료") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
