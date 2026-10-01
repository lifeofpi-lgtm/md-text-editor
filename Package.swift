// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDmaster",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MDmaster",
            path: "Sources/MDmaster"
        )
    ]
)
