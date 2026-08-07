// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FlowDelta",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FlowDeltaCore", targets: ["FlowDeltaCore"]),
        .library(name: "FlowDeltaAnalysis", targets: ["FlowDeltaAnalysis"]),
        .library(name: "FlowDeltaGit", targets: ["FlowDeltaGit"]),
        .library(name: "FlowDeltaExport", targets: ["FlowDeltaExport"]),
        .library(name: "FlowDeltaLayout", targets: ["FlowDeltaLayout"]),
        .library(name: "FlowDeltaUI", targets: ["FlowDeltaUI"]),
        .executable(name: "flowdelta", targets: ["FlowDeltaCLI"]),
        .executable(name: "FlowDeltaReference", targets: ["FlowDeltaReference"])
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", exact: "0.25.0"),
        // The plain 0.7.3 tag omits generated parser.c. Pin its paired,
        // source-complete 0.7.3 release commit instead.
        .package(
            url: "https://github.com/alex-pinkus/tree-sitter-swift.git",
            revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/hbmartin/HighlightKit.git", exact: "0.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", exact: "1.19.4")
    ],
    targets: [
        .target(name: "FlowDeltaCore"),
        .target(
            name: "FlowDeltaParse",
            dependencies: [
                "FlowDeltaCore",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift")
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
        .target(name: "FlowDeltaGit", dependencies: ["FlowDeltaCore"]),
        .target(name: "FlowDeltaExport", dependencies: ["FlowDeltaCore"]),
        .target(name: "FlowDeltaLayout", dependencies: ["FlowDeltaCore"]),
        .target(
            name: "FlowDeltaUI",
            dependencies: [
                "FlowDeltaCore",
                "FlowDeltaLayout",
                .product(name: "HighlightKit", package: "HighlightKit")
            ]
        ),
        .executableTarget(
            name: "FlowDeltaCLI",
            dependencies: [
                "FlowDeltaAnalysis",
                "FlowDeltaCore",
                "FlowDeltaExport",
                "FlowDeltaGit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "FlowDeltaReference",
            dependencies: [
                "FlowDeltaAnalysis",
                "FlowDeltaCore",
                "FlowDeltaGit",
                "FlowDeltaLayout",
                "FlowDeltaUI"
            ]
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
                "FlowDeltaLayout"
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FlowDeltaLayoutTests",
            dependencies: ["FlowDeltaCore", "FlowDeltaLayout"]
        ),
        .testTarget(
            name: "FlowDeltaUITests",
            dependencies: [
                "FlowDeltaAnalysis",
                "FlowDeltaCore",
                "FlowDeltaLayout",
                "FlowDeltaUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            resources: [.copy("__Snapshots__")]
        ),
        .testTarget(
            name: "FlowDeltaGitTests",
            dependencies: ["FlowDeltaCore", "FlowDeltaGit"]
        ),
        .testTarget(
            name: "FlowDeltaExportTests",
            dependencies: ["FlowDeltaCore", "FlowDeltaExport"]
        ),
        .testTarget(
            name: "FlowDeltaCLITests",
            dependencies: [
                "FlowDeltaCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
