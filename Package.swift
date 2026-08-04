// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FlowDelta",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "FlowDeltaCore", targets: ["FlowDeltaCore"]),
        .library(name: "FlowDeltaAnalysis", targets: ["FlowDeltaAnalysis"]),
        .library(name: "FlowDeltaLayout", targets: ["FlowDeltaLayout"]),
        .library(name: "FlowDeltaUI", targets: ["FlowDeltaUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", exact: "0.25.0"),
        // The plain 0.7.3 tag omits generated parser.c. Pin its paired,
        // source-complete 0.7.3 release commit instead.
        .package(
            url: "https://github.com/alex-pinkus/tree-sitter-swift.git",
            revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"
        ),
    ],
    targets: [
        .target(name: "FlowDeltaCore"),
        .target(
            name: "FlowDeltaParse",
            dependencies: [
                "FlowDeltaCore",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
            ]
        ),
        .target(name: "FlowDeltaMatch", dependencies: ["FlowDeltaCore"]),
        .target(
            name: "FlowDeltaFlow",
            dependencies: ["FlowDeltaCore", "FlowDeltaParse", "FlowDeltaMatch"]
        ),
        .target(
            name: "FlowDeltaAnalysis",
            dependencies: ["FlowDeltaCore", "FlowDeltaParse", "FlowDeltaMatch", "FlowDeltaFlow"]
        ),
        .target(name: "FlowDeltaLayout", dependencies: ["FlowDeltaCore"]),
        .target(
            name: "FlowDeltaUI",
            dependencies: ["FlowDeltaCore", "FlowDeltaLayout"]
        ),
        .testTarget(name: "FlowDeltaCoreTests", dependencies: ["FlowDeltaCore"]),
        .testTarget(
            name: "FlowDeltaAnalysisTests",
            dependencies: [
                "FlowDeltaCore",
                "FlowDeltaParse",
                "FlowDeltaMatch",
                "FlowDeltaFlow",
                "FlowDeltaAnalysis",
                "FlowDeltaLayout",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FlowDeltaLayoutTests",
            dependencies: ["FlowDeltaCore", "FlowDeltaLayout"]
        ),
        .testTarget(
            name: "FlowDeltaUITests",
            dependencies: ["FlowDeltaCore", "FlowDeltaLayout", "FlowDeltaUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
