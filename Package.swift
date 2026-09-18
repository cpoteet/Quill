// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Quill", targets: ["Quill"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Quill",
            dependencies: ["QuillKit"],
            path: "Sources/Quill"
        ),
        .target(
            name: "QuillKit",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/QuillKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "QuillTests",
            dependencies: [
                "QuillKit",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/QuillTests"
        ),
    ]
)
