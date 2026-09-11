// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HarborCore", targets: ["HarborCore"])],
    targets: [
        .target(name: "HarborCore", path: "Sources/HarborCore"),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"], path: "Tests/HarborCoreTests")
    ]
)
