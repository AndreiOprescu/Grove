// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Grove",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "GroveCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Grove",
            dependencies: ["GroveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GroveCoreTests",
            dependencies: ["GroveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GroveTests",
            dependencies: ["Grove", "GroveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
