import Foundation

struct PortInfo: Identifiable {
    let id = UUID()
    let port: UInt16
    let pid: Int32
    let processName: String
    let proto: String
    let uptime: String
}

struct PortScanner {
    func activePorts() -> [PortInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-iUDP", "-n", "-P", "-sTCP:LISTEN"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [PortInfo] = []
        let lines = output.components(separatedBy: "\n").dropFirst()

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            guard let pid = Int32(parts[1]) else { continue }
            let proto = String(parts[7])
            let addressField = String(parts[8])

            // 아웃바운드 연결(-> 포함)은 로컬 LISTEN/바인딩 포트가 아니므로 제외
            if addressField.contains("->") { continue }

            guard let portStr = addressField.split(separator: ":").last,
                  let port = UInt16(portStr) else { continue }

            if !results.contains(where: { $0.port == port && $0.pid == pid }) {
                let info = processInfo(pid: pid)
                let processName = info.name ?? String(parts[0])
                results.append(PortInfo(port: port, pid: pid, processName: processName, proto: proto, uptime: info.uptime))
            }
        }

        return results.sorted { $0.port < $1.port }
    }

    private func processInfo(pid: Int32) -> (name: String?, uptime: String) {
        let name = runPs(pid: pid, format: "comm=")
            .flatMap { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
        let uptime = runPs(pid: pid, format: "etime=").map { formatEtime($0) } ?? ""
        return (name, uptime)
    }

    private func runPs(pid: Int32, format: String) -> String? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-ww", "-p", "\(pid)", "-o", format]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = Pipe()
        guard (try? ps.run()) != nil else { return nil }
        ps.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out?.isEmpty == false ? out : nil
    }

    private func formatEtime(_ etime: String) -> String {
        var days = 0, hours = 0, minutes = 0, seconds = 0
        let parts = etime.components(separatedBy: "-")
        let timePart: String
        if parts.count == 2 { days = Int(parts[0]) ?? 0; timePart = parts[1] }
        else { timePart = parts[0] }
        let timeParts = timePart.components(separatedBy: ":")
        switch timeParts.count {
        case 3: hours = Int(timeParts[0]) ?? 0; minutes = Int(timeParts[1]) ?? 0; seconds = Int(timeParts[2]) ?? 0
        case 2: minutes = Int(timeParts[0]) ?? 0; seconds = Int(timeParts[1]) ?? 0
        default: seconds = Int(timeParts[0]) ?? 0
        }
        if days > 0    { return "\(days)d \(hours)h" }
        if hours > 0   { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    func isPortAvailable(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        var optVal: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    func processUsing(port: UInt16) -> PortInfo? {
        activePorts().first { $0.port == port }
    }

    // PID 프로세스 강제 종료 (SIGKILL)
    @discardableResult
    func killProcess(pid: Int32) -> (Bool, String?) {
        if Foundation.kill(pid, SIGKILL) == 0 {
            return (true, nil)
        } else {
            let msg: String
            switch errno {
            case EPERM:  msg = "권한 없음 — sudo 필요"
            case ESRCH:  msg = "프로세스가 이미 종료됨"
            default:     msg = String(cString: strerror(errno))
            }
            return (false, msg)
        }
    }
}
