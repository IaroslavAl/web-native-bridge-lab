// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BridgeLabCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "BridgeLabCore", targets: ["BridgeLabCore"])
    ],
    dependencies: [
        .package(path: "../native/TransportPackage")
    ],
    targets: [
        .target(
            name: "BridgeLabCore",
            dependencies: ["TransportPackage"]
        ),
        .testTarget(
            name: "BridgeLabCoreTests",
            dependencies: ["BridgeLabCore", "TransportPackage"]
        )
    ]
)
