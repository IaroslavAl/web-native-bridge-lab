// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TransportPackage",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TransportPackage", targets: ["TransportPackage"])
    ],
    targets: [
        .target(name: "TransportPackage"),
        .testTarget(name: "TransportPackageTests", dependencies: ["TransportPackage"])
    ]
)
