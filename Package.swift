// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SlatePDF",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "SlatePDF", targets: ["SlatePDF"]),
    ],
    targets: [
        .executableTarget(
            name: "SlatePDF",
            path: ".",
            exclude: [
                ".build",
                ".git",
                ".tmp",
                "Tests",
                "AGENTS.md",
                "CLAUDE.md",
                "PROJECT.md",
                "TASKS.md",
            ],
            sources: [
                "App",
                "Core",
                "UI",
                "Features",
            ]
        ),
        .testTarget(
            name: "SlatePDFTests",
            dependencies: ["SlatePDF"],
            path: "Tests/SlatePDFTests"
        ),
    ]
)
