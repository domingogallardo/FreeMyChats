// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FreeMyChats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FreeMyChats",
            targets: ["FreeMyChats"]
        )
    ],
    dependencies: [
        // This integration branch consumes the unreleased conversation-composition API.
        // Restore the remote dependency when SwiftWABackupAPI 5.0.0 is published.
        .package(path: "../SwiftWABackupAPI")
    ],
    targets: [
        .executableTarget(
            name: "FreeMyChats",
            dependencies: [
                .product(name: "SwiftWABackupAPI", package: "SwiftWABackupAPI")
            ]
        ),
        .testTarget(
            name: "FreeMyChatsTests",
            dependencies: ["FreeMyChats"]
        )
    ]
)
