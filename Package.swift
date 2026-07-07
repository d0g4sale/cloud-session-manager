// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CloudSessionManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CloudSessionManager",
            path: "Sources/CloudSessionManager"
        ),
        .testTarget(
            name: "CloudSessionManagerTests",
            dependencies: ["CloudSessionManager"],
            path: "Tests/CloudSessionManagerTests"
        )
    ]
)
