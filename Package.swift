// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DockStickForever",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DockStickForever",
            targets: ["DockStickApp"]
        ),
        .library(
            name: "DockStickCore",
            targets: ["DockStickCore"]
        ),
    ],
    targets: [
        // Core layer - pure geometry, no AppKit. Testable without a mouse.
        .target(
            name: "DockStickCore",
            dependencies: []
        ),

        // App layer - menu bar agent + CGEventTap
        .executableTarget(
            name: "DockStickApp",
            dependencies: ["DockStickCore"]
        ),

        .testTarget(
            name: "DockStickCoreTests",
            dependencies: ["DockStickCore"]
        ),
    ]
)
