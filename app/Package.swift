// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Datacom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Datacom",
            resources: [
                .copy("Resources/library.json"),
                .copy("Resources/web"),
            ]
        )
    ]
)
