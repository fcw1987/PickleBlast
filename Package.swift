// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PickleBlast",
    platforms: [.macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "PickleBlastCore", targets: ["PickleBlastCore"]),
        .library(name: "PickleBlastRendering", targets: ["PickleBlastRendering"])
    ],
    targets: [
        .target(name: "PickleBlastCore"),
        .target(name: "PickleBlastRendering", dependencies: ["PickleBlastCore"]),
        .target(name: "PickleBlastAppUI", dependencies: ["PickleBlastCore", "PickleBlastRendering"],
                path: "WatchApp", exclude: ["PickleBlastApp.swift", "Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy", "Art"]),
        .executableTarget(name: "RenderEvidence", dependencies: ["PickleBlastCore", "PickleBlastRendering"],
                          path: "Tools/RenderEvidence"),
        .testTarget(name: "PickleBlastRenderingTests", dependencies: ["PickleBlastRendering", "PickleBlastCore"]),
        .testTarget(name: "PickleBlastCoreTests", dependencies: ["PickleBlastCore"]),
        .testTarget(name: "PickleBlastAppUITests", dependencies: ["PickleBlastAppUI", "PickleBlastCore"])
    ],
    swiftLanguageVersions: [.v5]
)
