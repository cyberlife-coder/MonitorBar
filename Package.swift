// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MonitorBar",
    platforms: [ .macOS(.v13) ],
    products: [
        .executable(name: "MonitorBar", targets: ["MonitorBar"]),
        .library(name: "MonitorBarCore", targets: ["MonitorBarCore"])
    ],
    targets: [
        .target(
            name: "MonitorBarCore",
            path: "Sources/MonitorBarCore"
        ),
        .executableTarget(
            name: "MonitorBar",
            dependencies: ["MonitorBarCore"],
            path: "Sources/MonitorBar"
        ),
        .executableTarget(
            name: "SnapshotTool",
            dependencies: ["MonitorBarCore"],
            path: "Sources/SnapshotTool"
        ),
        .testTarget(
            name: "MonitorBarTests",
            dependencies: ["MonitorBarCore"],
            path: "Tests/MonitorBarTests"
        )
    ]
)
