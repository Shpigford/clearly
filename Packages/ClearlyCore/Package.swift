// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClearlyCore",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "ClearlyCore", targets: ["ClearlyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/brokenhandsio/cmark-gfm.git", from: "2.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ClearlyCore",
            dependencies: [
                .product(name: "cmark", package: "cmark-gfm"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ClearlyCoreTests",
            dependencies: ["ClearlyCore"]
        ),
    ]
)
