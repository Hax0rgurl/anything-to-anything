// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMediaConverter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexMediaConverter", targets: ["CodexMediaConverter"])
    ],
    targets: [
        .executableTarget(
            name: "CodexMediaConverter",
            path: "Sources/CodexMediaConverter"
        )
    ],
    swiftLanguageModes: [.v5]
)
