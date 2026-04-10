// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Walter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Walter",
            path: "Sources/Walter",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/menubar_icon.png"),
                .copy("Resources/menubar_icon@2x.png"),
            ]
        ),
    ]
)
