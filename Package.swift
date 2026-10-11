// swift-tools-version: 5.9
// agent-usage: zero external dependencies.
// Pure Apple frameworks only: Foundation, Security, AppKit.

import PackageDescription

let package = Package(
    name: "agent-usage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "agent-usage", targets: ["AgentUsage"]),
        .executable(name: "AgentUsageBar", targets: ["AgentUsageBar"]),
        .library(name: "AgentUsageCore", targets: ["AgentUsageCore"]),
    ],
    targets: [
        .target(
            name: "AgentUsageCore",
            path: "Sources/AgentUsageCore"
        ),
        .executableTarget(
            name: "AgentUsage",
            dependencies: ["AgentUsageCore"],
            path: "Sources/AgentUsage"
        ),
        .executableTarget(
            name: "AgentUsageBar",
            dependencies: ["AgentUsageCore"],
            path: "Sources/AgentUsageBar"
        ),
        // Dependency-free self-test runnable under Command Line Tools (no
        // full Xcode / XCTest needed): `swift run AgentUsageSelfTest`.
        .executableTarget(
            name: "AgentUsageSelfTest",
            dependencies: ["AgentUsageCore"],
            path: "Sources/AgentUsageSelfTest"
        ),
        // Renders the README image from the real parsers and Output with
        // sample data: `swift run AgentUsageSnapshot docs/img/menubar.png`.
        .executableTarget(
            name: "AgentUsageSnapshot",
            dependencies: ["AgentUsageCore"],
            path: "Sources/AgentUsageSnapshot"
        ),
    ]
)
