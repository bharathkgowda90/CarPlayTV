// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CarPlayTVKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "SourcesKit", targets: ["SourcesKit"]),
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
        .library(name: "SafetyKit", targets: ["SafetyKit"]),
    ],
    targets: [
        .target(name: "SourcesKit"),
        .target(name: "PlaybackKit", dependencies: ["SourcesKit"]),
        .target(name: "SafetyKit"),
        .testTarget(name: "SourcesKitTests", dependencies: ["SourcesKit"]),
        .testTarget(name: "SafetyKitTests", dependencies: ["SafetyKit"]),
    ],
    swiftLanguageModes: [.v5]
)
