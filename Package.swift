// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-markdown-table-fix",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "MarkdownTableFixer",
            targets: ["MarkdownTableFixer"]
        ),
    ],
    targets: [
        .target(
            name: "MarkdownTableFixer"
        ),
        .testTarget(
            name: "MarkdownTableFixerTests",
            dependencies: ["MarkdownTableFixer"]
        ),
    ]
)
