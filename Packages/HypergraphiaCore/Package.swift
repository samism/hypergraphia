// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HypergraphiaCore",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "HypergraphiaCore", targets: ["HypergraphiaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/brokenhandsio/cmark-gfm.git", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "HypergraphiaCore",
            dependencies: [
                .product(name: "cmark", package: "cmark-gfm"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "HypergraphiaCoreTests",
            dependencies: ["HypergraphiaCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
