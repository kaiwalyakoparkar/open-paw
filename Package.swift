// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentMeow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentMeow", targets: ["AgentMeow"]),
        .executable(name: "AgentMeowCheck", targets: ["AgentMeowCheck"]),
        .library(name: "AgentMeowCore", targets: ["AgentMeowCore"]),
    ],
    targets: [
        .target(
            name: "AgentMeowCore",
            path: "AgentMeowCore"
        ),
        .executableTarget(
            name: "AgentMeow",
            dependencies: ["AgentMeowCore"],
            path: "AgentMeow",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/cat_avatar.png"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "AgentMeowCheck",
            dependencies: ["AgentMeowCore"],
            path: "AgentMeowTests"
        ),
    ]
)
