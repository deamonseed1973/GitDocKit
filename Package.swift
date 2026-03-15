// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GitDocKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "GitDocKit", targets: ["GitDocKit"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "GitDocKit", dependencies: []),
        .testTarget(name: "GitDocKitTests", dependencies: ["GitDocKit"]),
    ]
)
