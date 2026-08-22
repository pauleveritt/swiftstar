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
        .target(
            name: "SwiftStarAppKit",
            dependencies: ["SwiftStarKit"]
        ),
        .executableTarget(
            name: "SwiftStar",
            dependencies: ["SwiftStarKit", "SwiftStarAppKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SwiftStarKitTests",
            dependencies: ["SwiftStarKit"],
            plugins: ["FastTierGuard"]
        ),
        .testTarget(
            name: "SwiftStarIntegrationTests",
            dependencies: ["SwiftStarKit", "SwiftStarAppKit"]
        ),
        .executableTarget(name: "FastTierGuardTool"),
        .plugin(
            name: "FastTierGuard",
            capability: .buildTool(),
            dependencies: [.target(name: "FastTierGuardTool")]
        ),
    ]
)
