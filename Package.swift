// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacDualMiner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MacDualMiner",
            path: "Sources/MacDualMiner",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "MacDualMinerTests",
            dependencies: ["MacDualMiner"],
            path: "Tests/MacDualMinerTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
