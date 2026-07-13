// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GhostRaceKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GhostRaceKit", targets: ["GhostRaceKit"])
    ],
    targets: [
        .target(name: "GhostRaceKit"),
        .testTarget(
            name: "GhostRaceKitTests",
            dependencies: ["GhostRaceKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
