// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftStar",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftStarKit", targets: ["SwiftStarKit"]),
        .executable(name: "SwiftStar", targets: ["SwiftStar"]),
    ],
    dependencies: [
        // Fork of Lakr233/MarkdownView (battle-tested in FlowDown), branched off
        // the 3.9.1 revision FlowDown ships, with two DS4 patches on the
        // `ds4-patches` branch: (1) code blocks reserve their actual rendered
        // height so they no longer overlap following text; (2) emphasis renders
        // as italic instead of an orange underline. Pinned by revision for
        // reproducible builds. Upstream: https://github.com/Lakr233/MarkdownView
        // — re-base the patches when bumping. (Provenance: ds4-control's
        // Package.swift; facts cross, code does not.)
        .package(
            url: "https://github.com/notatestuser/MarkdownView",
            revision: "d83032f91844e5365f49a174d9940036790e434c"),
    ],
    targets: [
        .target(name: "SwiftStarKit"),
        .target(
            name: "SwiftStarAppKit",
            dependencies: ["SwiftStarKit"],
            resources: [.process("Resources")],
            linkerSettings: [
                // Private dyld-cache lib for power (Apple Silicon); cited from
                // ds4-control's Package.swift (facts cross, code does not).
                .linkedLibrary("IOReport")
            ]
        ),
        .executableTarget(
            name: "SwiftStar",
            dependencies: [
                "SwiftStarKit",
                "SwiftStarAppKit",
                .product(name: "MarkdownView", package: "MarkdownView"),
                .product(name: "MarkdownParser", package: "MarkdownView"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "swiftstar-drive", dependencies: ["SwiftStarKit"]),
        .executableTarget(name: "swiftstar-agenttest", dependencies: ["SwiftStarKit", "SwiftStarAppKit"]),
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
