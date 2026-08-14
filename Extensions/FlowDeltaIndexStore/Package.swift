// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FlowDeltaIndexStoreExtension",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FlowDeltaIndexStore", targets: ["FlowDeltaIndexStore"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git",
            revision: "c993f4fb4f321fae1945e96a2377742f24e132f4"
        )
    ],
    targets: [
        .target(
            name: "FlowDeltaIndexStore",
            dependencies: [
                .product(name: "FlowDeltaCore", package: "FlowDelta"),
                .product(name: "IndexStoreDB", package: "indexstore-db")
            ]
        ),
        .testTarget(
            name: "FlowDeltaIndexStoreTests",
            dependencies: [
                "FlowDeltaIndexStore",
                .product(name: "FlowDeltaCore", package: "FlowDelta"),
                .product(name: "IndexStoreDB", package: "indexstore-db")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
