// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MultiOutputVolume",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MultiOutputVolume", targets: ["MultiOutputVolume"])
    ],
    targets: [
        .executableTarget(
            name: "MultiOutputVolume",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
