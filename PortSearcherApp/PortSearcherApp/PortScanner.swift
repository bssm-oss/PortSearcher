import Foundation

struct PortInfo: Identifiable {
    let id = UUID()
    let port: UInt16
    let pid: Int32
    let processName: String
    let proto: String
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

            let processName = String(parts[0])
            guard let pid = Int32(parts[1]) else { continue }
            let proto = String(parts[7])
            let addressField = String(parts[8])

            guard let portStr = addressField.split(separator: ":").last,
                  let port = UInt16(portStr) else { continue }

            if !results.contains(where: { $0.port == port && $0.pid == pid }) {
                results.append(PortInfo(port: port, pid: pid, processName: processName, proto: proto))
            }
        }

        return results.sorted { $0.port < $1.port }
    }

    func isPortAvailable(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
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
}
