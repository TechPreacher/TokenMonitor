// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMonitorKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TokenMonitorKit", targets: ["TokenMonitorKit"])
    ],
    targets: [
        .target(name: "TokenMonitorKit"),
        .testTarget(name: "TokenMonitorKitTests", dependencies: ["TokenMonitorKit"]),
    ]
)
