// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "hummingbird-knowledge-server",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            from: "0.9.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.5.0"
        ),
        .package(
            url: "https://github.com/swift-server/swift-service-lifecycle.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "HummingbirdKnowledgeServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/HummingbirdKnowledgeServer",
            resources: [
                .copy("KnowledgeBase/knowledge.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "HummingbirdKnowledgeServerTests",
            dependencies: [
                .target(name: "HummingbirdKnowledgeServer"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/HummingbirdKnowledgeServerTests",
            resources: [
                .copy("Fixtures/knowledge-test.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
