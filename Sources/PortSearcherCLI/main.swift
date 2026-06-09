import Foundation
import PortSearcherCore

let scanner = PortScanner()
let args = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    PortSearcher CLI

    사용법:
      portsearcher                  현재 사용 중인 포트 목록 출력
      portsearcher check <포트번호>  특정 포트 사용 가능 여부 확인
      portsearcher info  <포트번호>  해당 포트를 사용 중인 프로세스 정보
      portsearcher help             도움말
    """)
}

func listActivePorts() {
    let ports = scanner.activePorts()
    if ports.isEmpty {
        print("사용 중인 포트가 없습니다.")
        return
    }
    let header = "PORT    ".padding(toLength: 8, withPad: " ", startingAt: 0)
        + "PID       ".padding(toLength: 10, withPad: " ", startingAt: 0)
        + "PROTO   ".padding(toLength: 8, withPad: " ", startingAt: 0)
        + "PROCESS"
    print(header)
    print(String(repeating: "-", count: 44))
    for info in ports {
        let line = "\(info.port)".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "\(info.pid)".padding(toLength: 10, withPad: " ", startingAt: 0)
            + info.proto.padding(toLength: 8, withPad: " ", startingAt: 0)
            + info.processName
        print(line)
    }
    print("\n총 \(ports.count)개 포트 사용 중")
}

func checkPort(_ portStr: String) {
    guard let port = UInt16(portStr) else {
        print("오류: '\(portStr)'은(는) 올바른 포트 번호가 아닙니다. (1–65535)")
        exit(1)
    }
    if scanner.isPortAvailable(port) {
        print("✅ 포트 \(port): 사용 가능")
    } else {
        print("❌ 포트 \(port): 사용 중")
        if let info = scanner.processUsing(port: port) {
            print("   프로세스: \(info.processName) (PID: \(info.pid))")
        }
    }
}

func portInfo(_ portStr: String) {
    guard let port = UInt16(portStr) else {
        print("오류: '\(portStr)'은(는) 올바른 포트 번호가 아닙니다.")
        exit(1)
    }
    if let info = scanner.processUsing(port: port) {
        print("포트 \(port) 정보:")
        print("  프로세스: \(info.processName)")
        print("  PID:     \(info.pid)")
        print("  프로토콜: \(info.proto)")
    } else if scanner.isPortAvailable(port) {
        print("포트 \(port)는 현재 사용 중이지 않습니다 (사용 가능).")
    } else {
        print("포트 \(port)는 사용 중이지만 프로세스 정보를 가져올 수 없습니다.")
    }
}

let command = args.first ?? "list"

switch command {
case "list":
    listActivePorts()
case "check":
    guard let port = args.dropFirst().first else {
        print("오류: 포트 번호를 입력하세요. 예: portsearcher check 8080")
        exit(1)
    }
    checkPort(String(port))
case "info":
    guard let port = args.dropFirst().first else {
        print("오류: 포트 번호를 입력하세요. 예: portsearcher info 8080")
        exit(1)
    }
    portInfo(String(port))
case "help", "--help", "-h":
    printHelp()
default:
    if UInt16(command) != nil {
        checkPort(command)
    } else {
        print("알 수 없는 명령어: \(command)")
        printHelp()
        exit(1)
    }
}
