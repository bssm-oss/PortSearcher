// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortSearcher",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PortSearcherCore",
            path: "Sources/PortSearcherCore"
        ),
        .executableTarget(
            name: "PortSearcherCLI",
            dependencies: ["PortSearcherCore"],
            path: "Sources/PortSearcherCLI"
        ),
    ]
)
