// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Ghostwriter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Ghostwriter",
            path: "Sources/Ghostwriter",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "GhostwriterTests",
            dependencies: ["Ghostwriter"],
            path: "Tests/GhostwriterTests"
        ),
    ]
)
