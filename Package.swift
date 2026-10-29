// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarMatrix",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BarMatrix", path: "Sources/BarMatrix")
    ]
)
