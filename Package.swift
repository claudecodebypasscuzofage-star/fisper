// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Fisper",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Fisper",
            path: "Sources/Fisper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
