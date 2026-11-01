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
            // build.sh copies Resources into the app bundle.
            exclude: [
                "Resources",
                "AI/CLAUDE.md",
                "API/CLAUDE.md",
                "App/CLAUDE.md",
                "Views/CLAUDE.md",
                "Views/AI/CLAUDE.md",
                "Views/Editor/CLAUDE.md",
                "Views/Media/CLAUDE.md",
                "Views/Settings/CLAUDE.md",
                "Views/Sidebar/CLAUDE.md",
            ]
        ),
        .testTarget(
            name: "QuillTests",
            dependencies: ["QuillKit"],
            path: "Tests/QuillTests"
        ),
    ]
)
