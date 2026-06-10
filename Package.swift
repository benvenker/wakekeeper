// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "WakeKeeper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WakeKeeper", targets: ["WakeKeeperApp"])
    ],
    targets: [
        .target(name: "WakeKeeperCore"),
        .executableTarget(
            name: "WakeKeeperApp",
            dependencies: ["WakeKeeperCore"]
        ),
        .testTarget(
            name: "WakeKeeperCoreTests",
            dependencies: ["WakeKeeperCore"]
        )
    ]
)
