// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FocusDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FocusDockCore",
            targets: ["FocusDockCore"]
        ),
        .executable(
            name: "FocusDock",
            targets: ["FocusDock"]
        ),
        .executable(
            name: "focusdock-cli",
            targets: ["FocusDockCLI"]
        )
    ],
    targets: [
        .target(
            name: "FocusDockCore",
            path: "Sources/FocusDockCore"
        ),
        .executableTarget(
            name: "FocusDock",
            dependencies: ["FocusDockCore"],
            path: "Sources/FocusDock"
        ),
        .executableTarget(
            name: "FocusDockCLI",
            dependencies: ["FocusDockCore"],
            path: "Sources/FocusDockCLI"
        ),
        .testTarget(
            name: "FocusDockTests",
            dependencies: ["FocusDockCore"],
            path: "Tests/FocusDockTests"
        )
    ]
)
