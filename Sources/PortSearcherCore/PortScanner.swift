import Foundation
import Network

public struct PortInfo: Identifiable, Sendable {
    public let id = UUID()
    public let port: UInt16
    public let pid: Int32
    public let processName: String
    public let proto: String

    public init(port: UInt16, pid: Int32, processName: String, proto: String) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.proto = proto
    }
}

public struct PortScanner {
    public init() {}

    // lsof 로 현재 사용 중인 포트 목록 가져오기
    public func activePorts() -> [PortInfo] {
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

            // 포트 파싱: "*.8080" or "127.0.0.1:8080" or "[::]:8080"
            guard let portStr = addressField.split(separator: ":").last,
                  let port = UInt16(portStr) else { continue }

            // 중복 제거
            if !results.contains(where: { $0.port == port && $0.pid == pid }) {
                results.append(PortInfo(port: port, pid: pid, processName: processName, proto: proto))
            }
        }

        return results.sorted { $0.port < $1.port }
    }

    // 포트가 사용 가능한지 확인 (TCP 바인딩 시도)
    public func isPortAvailable(_ port: UInt16) -> Bool {
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

    // 포트를 사용 중인 프로세스 정보 반환
    public func processUsing(port: UInt16) -> PortInfo? {
        activePorts().first { $0.port == port }
    }
}
