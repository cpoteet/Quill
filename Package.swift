// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WPWriter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WPWriter", targets: ["WPWriter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "WPWriter",
            dependencies: ["WPWriterKit"],
            path: "Sources/WPWriter"
        ),
        .target(
            name: "WPWriterKit",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/WPWriterKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "WPWriterTests",
            dependencies: [
                "WPWriterKit",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/WPWriterTests"
        ),
    ]
)
