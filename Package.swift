// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftStar",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftStarKit", targets: ["SwiftStarKit"]),
        .executable(name: "SwiftStar", targets: ["SwiftStar"]),
    ],
    targets: [
        .target(name: "SwiftStarKit"),
        .executableTarget(name: "SwiftStar", dependencies: ["SwiftStarKit"]),
        .testTarget(
            name: "SwiftStarKitTests",
            dependencies: ["SwiftStarKit"]
        ),
        .testTarget(
            name: "SwiftStarIntegrationTests",
            dependencies: ["SwiftStarKit"]
        ),
    ]
)
