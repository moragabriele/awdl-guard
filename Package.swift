// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AWDLGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "awdl-guardd", targets: ["awdl-guardd"]),
        .executable(name: "awdl-guardctl", targets: ["awdl-guardctl"]),
        .executable(name: "AWDLGuardAgent", targets: ["AWDLGuardAgent"]),
    ],
    targets: [
        // Objective-C core derived from AWDLControl (MIT). Holds awdl0 down.
        .target(name: "AWDLCore"),
        // Settings, policy, XPC protocol and client shared by every binary.
        .target(name: "AWDLShared"),
        .executableTarget(
            name: "awdl-guardd",
            dependencies: ["AWDLCore", "AWDLShared"],
            linkerSettings: [.linkedFramework("SystemConfiguration")]
        ),
        .executableTarget(
            name: "awdl-guardctl",
            dependencies: ["AWDLShared"]
        ),
        .executableTarget(
            name: "AWDLGuardAgent",
            dependencies: ["AWDLShared"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreAudio")]
        ),
        .testTarget(name: "AWDLSharedTests", dependencies: ["AWDLShared"]),
    ]
)
