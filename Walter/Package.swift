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
            ]
        ),
        .testTarget(
            name: "WalterTests",
            dependencies: ["Walter"],
            path: "Tests/WalterTests"
        ),
    ]
)
