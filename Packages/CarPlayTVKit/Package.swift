// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CarPlayTVKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "SourcesKit", targets: ["SourcesKit"]),
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
        .library(name: "SafetyKit", targets: ["SafetyKit"]),
        .library(name: "LibraryKit", targets: ["LibraryKit"]),
        .library(name: "ReceiverKit", targets: ["ReceiverKit"]),
        .library(name: "MirrorKit", targets: ["MirrorKit"]),
    ],
    targets: [
        .target(name: "SourcesKit"),
        .target(name: "PlaybackKit", dependencies: ["SourcesKit"]),
        .target(name: "SafetyKit"),
        .target(name: "LibraryKit", dependencies: ["SourcesKit"]),
        .target(name: "ReceiverKit"),
        .target(name: "MirrorKit"),
        .testTarget(name: "SourcesKitTests", dependencies: ["SourcesKit"]),
        .testTarget(name: "SafetyKitTests", dependencies: ["SafetyKit"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit", "SourcesKit"]),
        .testTarget(name: "PlaybackKitTests", dependencies: ["PlaybackKit"]),
        .testTarget(name: "ReceiverKitTests", dependencies: ["ReceiverKit"]),
        .testTarget(name: "MirrorKitTests", dependencies: ["MirrorKit"]),
    ],
    swiftLanguageModes: [.v5]
)
