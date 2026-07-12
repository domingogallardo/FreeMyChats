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
            from: "4.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "FreeMyChats",
            dependencies: [
                .product(name: "SwiftWABackupAPI", package: "SwiftWABackupAPI")
            ]
        )
    ]
)
