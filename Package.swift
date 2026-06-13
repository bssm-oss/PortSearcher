// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortSearcher",

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
