// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Serein",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Serein", targets: ["Serein"]),
    ],
    targets: [
        .executableTarget(
            name: "Serein",
            path: ".",
            exclude: [
                ".build",
                ".git",
                ".tmp",
                "Tests",
                "AGENTS.md",
                "CLAUDE.md",
                "CHANGELOG.md",
                "LICENSE",
                "PROJECT.md",
                "TASKS.md",
                "Justfile",
                "README.md",
                "REVIEW.md",
                "Resources",
                "Scripts",
                "Website",
                "build",
            ],
            sources: [
                "App",
                "Core",
                "UI",
                "Features",
            ]
        ),
        .testTarget(
            name: "SereinTests",
            dependencies: ["Serein"],
            path: "Tests/SereinTests"
        ),
    ]
)
