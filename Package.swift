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
    dependencies: [
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", from: "0.4.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "GitDocKit", dependencies: ["SwiftGitX", "ZIPFoundation"]),
        .testTarget(name: "GitDocKitTests", dependencies: ["GitDocKit"]),
    ]
)
