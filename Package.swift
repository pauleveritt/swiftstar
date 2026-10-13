// swift-tools-version: 6.2
import PackageDescription

/// Settings every target this package defines shares (SU.4 spec, decisions D4
/// and D5). Dependencies are not affected: warnings as errors applies to our
/// own code only.
let common: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    // Xcode's "Approachable Concurrency" pair, enabled by name in SwiftPM.
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]

/// UI, app and the tests that touch UI types run on the main actor by default.
let mainActor: [SwiftSetting] = common + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "SwiftStar",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftStarKit", targets: ["SwiftStarKit"]),
        // Exists so Xcode generates a SwiftStarUI scheme for previews (no other consumer).
        .library(name: "SwiftStarUI", targets: ["SwiftStarUI"]),
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
        .target(name: "SwiftStarKit", swiftSettings: common),
        .target(
            name: "SwiftStarEngine",
            dependencies: ["SwiftStarKit"],
            // The session report (AN.1); `just last` runs the same file.
            resources: [.copy("Resources/session_last.py")],
            swiftSettings: common
        ),
        // The views live in a library target, not the executable: Xcode cannot
        // preview inside an executable target of a bare package (it needs the
        // Xcode-only ENABLE_DEBUG_DYLIB setting).
        .target(
            name: "SwiftStarUI",
            dependencies: [
                "SwiftStarKit",
                "SwiftStarEngine",
                .product(name: "MarkdownView", package: "MarkdownView"),
                .product(name: "MarkdownParser", package: "MarkdownView"),
            ],
            swiftSettings: mainActor
        ),
        .executableTarget(
            name: "SwiftStar",
            dependencies: ["SwiftStarUI"],
            // The icon is copied into the .app by Tools/make-app.sh, not
            // bundled as a SwiftPM resource (it shipped twice).
            exclude: ["Resources"],
            swiftSettings: mainActor
        ),
        .testTarget(
            name: "SwiftStarKitTests",
            dependencies: ["SwiftStarKit"],
            swiftSettings: common
        ),
        .testTarget(
            name: "SwiftStarIntegrationTests",
            dependencies: ["SwiftStarKit", "SwiftStarEngine", "SwiftStarUI"],
            swiftSettings: mainActor
        ),
    ]
)
