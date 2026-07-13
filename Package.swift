// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FreeMyChats",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FreeMyChats",
            targets: ["FreeMyChats"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/domingogallardo/SwiftWABackupAPI.git",
            revision: "10aaadbf45f7692d051873b36f5860a1eeac289a"
        )
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
