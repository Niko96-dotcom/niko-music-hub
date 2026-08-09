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
        .library(
            name: "FeatureStemSeparation",
            targets: ["FeatureStemSeparation"]
        ),
        .executable(
            name: "NikoMusicHub",
            targets: ["NikoMusicHub"]
        ),
        .executable(
            name: "NikoMusicCoreSelfTest",
            targets: ["NikoMusicCoreSelfTest"]
        ),
        .executable(
            name: "NikoMusicHubCLI",
            targets: ["NikoMusicHubCLI"]
        )
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: ["NikoMusicCore"]
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
        .executableTarget(
            name: "NikoMusicHubCLI",
            dependencies: ["NikoMusicCore"]
        ),
        .target(
            name: "FeatureBPMTapper",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "FeatureAudioConverter",
            dependencies: ["AppCore", "NikoMusicCore"]
        ),
        .target(
            name: "FeatureAudioRecorder",
            dependencies: ["AppCore", "NikoMusicCore"]
        ),
        .target(
            name: "FeatureDownloader",
            dependencies: ["AppCore", "NikoMusicCore"]
        ),
        .target(
            name: "FeatureArchiveBrowser",
            dependencies: ["AppCore", "NikoMusicCore"]
        ),
        .target(
            name: "FeatureStemSeparation",
            dependencies: ["AppCore", "FeatureDownloader", "NikoMusicCore"]
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
                "FeatureDownloader",
                "FeatureStemSeparation"
            ]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "NikoMusicCore", "FeatureArchiveBrowser"]
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
        ),
        .testTarget(
            name: "FeatureStemSeparationTests",
            dependencies: ["FeatureStemSeparation", "AppCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
