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
            exact: "4.3.3"
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
