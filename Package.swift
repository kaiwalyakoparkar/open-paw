// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenPaw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenPaw", targets: ["OpenPaw"]),
        .executable(name: "OpenPawCheck", targets: ["OpenPawCheck"]),
        .library(name: "OpenPawCore", targets: ["OpenPawCore"]),
    ],
    targets: [
        .target(
            name: "OpenPawCore",
            path: "OpenPawCore"
        ),
        .executableTarget(
            name: "OpenPaw",
            dependencies: ["OpenPawCore"],
            path: "OpenPaw",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/cat_avatar.png"),
                .copy("Resources/harness_hermes.png"),
                .copy("Resources/harness_claude.png"),
                .copy("Resources/harness_codex.png"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "OpenPawCheck",
            dependencies: ["OpenPawCore"],
            path: "OpenPawTests"
        ),
    ]
)
