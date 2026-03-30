// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortPilot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "portpilot",
            targets: ["PortKillerCLI"]
        ),
        .executable(
            name: "portpilot-tui",
            targets: ["PortPilotTUI"]
        ),
        // Reusable TUI engine — zero-dependency terminal UI framework
        .library(
            name: "TerminalTUI",
            targets: ["TerminalTUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        // Shared library with PortManager
        .target(
            name: "PortManagerLib",
            dependencies: [],
            path: "Sources/PortManagerLib"
        ),

        // CLI tool
        .executableTarget(
            name: "PortKillerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "PortManagerLib"
            ],
            path: "Sources/PortKillerCLI"
        ),

        // Reusable TUI engine — zero dependencies, cross-platform (macOS + Linux + WSL)
        .target(
            name: "TerminalTUI",
            dependencies: [],
            path: "Sources/TerminalTUI"
        ),

        // PortPilot TUI app — uses TerminalTUI + PortManagerLib
        .executableTarget(
            name: "PortPilotTUI",
            dependencies: [
                "PortManagerLib",
                "TerminalTUI",
            ],
            path: "Sources/PortPilotTUI"
        ),
    ]
)
