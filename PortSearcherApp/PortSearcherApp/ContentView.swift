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

    private let scanner = PortScanner()

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
            Divider()
            CheckPanel(vm: vm)
            Divider()
            PortList(vm: vm)
            Divider()
            BottomBar()
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { vm.refresh() }
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
                            PortRow(info: info)
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
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
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
