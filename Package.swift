// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Snap2",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Snap2",
            path: "Sources/Snap2"
        )
    ]
)
