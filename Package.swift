// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMischief",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacMischief",
            path: "Sources/MacMischief"
        )
    ],
    swiftLanguageModes: [.v5]
)
