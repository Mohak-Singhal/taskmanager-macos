// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskManagerNative",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TaskManagerNative",
            path: "Sources/TaskManagerNative",
            linkerSettings: [
                .linkedFramework("DiskArbitration")
            ]
        ),
        .testTarget(
            name: "TaskManagerNativeTests",
            dependencies: ["TaskManagerNative"],
            path: "Tests/TaskManagerNativeTests"
        )
    ]
)
