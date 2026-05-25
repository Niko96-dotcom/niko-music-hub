// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OutsideCubaseHub",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .library(
            name: "AppCore",
            targets: ["AppCore"]
        ),
        .library(
            name: "FeatureBPMTapper",
            targets: ["FeatureBPMTapper"]
        ),
        .library(
            name: "FeatureAudioConverter",
            targets: ["FeatureAudioConverter"]
        ),
        .library(
            name: "FeatureAudioRecorder",
            targets: ["FeatureAudioRecorder"]
        ),
        .library(
            name: "FeatureDownloader",
            targets: ["FeatureDownloader"]
        ),
        .executable(
            name: "OutsideCubaseHub",
            targets: ["OutsideCubaseHub"]
        )
    ],
    targets: [
        .target(
            name: "AppCore"
        ),
        .target(
            name: "FeatureBPMTapper",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "FeatureAudioConverter",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "FeatureAudioRecorder",
            dependencies: ["AppCore", "FeatureAudioConverter"]
        ),
        .target(
            name: "FeatureDownloader",
            dependencies: ["AppCore"]
        ),
        .executableTarget(
            name: "OutsideCubaseHub",
            dependencies: [
                "AppCore",
                "FeatureBPMTapper",
                "FeatureAudioConverter",
                "FeatureAudioRecorder",
                "FeatureDownloader"
            ]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        ),
        .testTarget(
            name: "FeatureBPMTapperTests",
            dependencies: ["FeatureBPMTapper"]
        ),
        .testTarget(
            name: "FeatureAudioConverterTests",
            dependencies: ["FeatureAudioConverter", "AppCore"]
        ),
        .testTarget(
            name: "FeatureAudioRecorderTests",
            dependencies: ["FeatureAudioRecorder", "FeatureAudioConverter", "AppCore"]
        ),
        .testTarget(
            name: "FeatureDownloaderTests",
            dependencies: ["FeatureDownloader", "AppCore"]
        )
    ]
)
