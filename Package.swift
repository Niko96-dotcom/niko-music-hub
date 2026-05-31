// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NikoMusicHub",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .library(
            name: "AppCore",
            targets: ["AppCore"]
        ),
        .library(
            name: "NikoMusicCore",
            targets: ["NikoMusicCore"]
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
        .library(
            name: "FeatureArchiveBrowser",
            targets: ["FeatureArchiveBrowser"]
        ),
        .executable(
            name: "NikoMusicHub",
            targets: ["NikoMusicHub"]
        ),
        .executable(
            name: "NikoMusicCoreSelfTest",
            targets: ["NikoMusicCoreSelfTest"]
        )
    ],
    targets: [
        .target(
            name: "AppCore"
        ),
        .target(
            name: "NikoMusicCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NikoMusicCoreSelfTest",
            dependencies: ["NikoMusicCore"]
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
            dependencies: ["AppCore"]
        ),
        .target(
            name: "FeatureDownloader",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "FeatureArchiveBrowser",
            dependencies: ["AppCore", "NikoMusicCore"]
        ),
        .executableTarget(
            name: "NikoMusicHub",
            dependencies: [
                "AppCore",
                "NikoMusicCore",
                "FeatureArchiveBrowser",
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
            name: "NikoMusicCoreTests",
            dependencies: ["NikoMusicCore"]
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
            dependencies: ["FeatureAudioRecorder", "AppCore"]
        ),
        .testTarget(
            name: "FeatureDownloaderTests",
            dependencies: ["FeatureDownloader", "AppCore"]
        ),
        .testTarget(
            name: "FeatureArchiveBrowserTests",
            dependencies: ["FeatureArchiveBrowser", "NikoMusicCore", "AppCore"]
        )
    ]
)
