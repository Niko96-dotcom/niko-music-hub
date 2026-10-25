// swift-tools-version: 6.0

import PackageDescription

// Every target builds with warnings as errors, in every build: `swift build`,
// `swift test`, ./script/ci.sh, ci-release.sh and the app bundle. Clean-build
// warnings were cleared by hand twice (77d2d6d, 2e79a4f) and came back, and an
// unused non-discardable result (a refused save) is only a warning otherwise.
// PackageSettingsSourceTests fails when a target leaves this out.
// The flag cannot promote a warning Swift downgraded itself (a call into isolation
// inferred from a @preconcurrency protocol such as SwiftUI's View): ./script/ci.sh
// fails on those through a clean build.
let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

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
            name: "ProjectVaultRuntime",
            targets: ["ProjectVaultRuntime"]
        ),
        .library(
            name: "AppUpdates",
            targets: ["AppUpdates"]
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
    dependencies: [
        // Pinned exactly: the appcast enclosure signature contract depends on the
        // signing tools shipped alongside this exact framework build.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: ["NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "ProjectVaultRuntime",
            dependencies: ["AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "AppUpdates",
            dependencies: [
                "AppCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "NikoMusicCore",
            swiftSettings: strictSwiftSettings,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NikoMusicCoreSelfTest",
            dependencies: ["NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "NikoMusicHubCLI",
            dependencies: ["NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureBPMTapper",
            dependencies: ["AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureAudioConverter",
            dependencies: ["AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureAudioRecorder",
            dependencies: ["AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureDownloader",
            dependencies: ["AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureArchiveBrowser",
            dependencies: ["AppCore", "NikoMusicCore", "ProjectVaultRuntime"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "FeatureStemSeparation",
            dependencies: ["AppCore", "FeatureDownloader", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "NikoMusicHub",
            dependencies: [
                "AppCore",
                "AppUpdates",
                "NikoMusicCore",
                "ProjectVaultRuntime",
                "FeatureArchiveBrowser",
                "FeatureBPMTapper",
                "FeatureAudioConverter",
                "FeatureAudioRecorder",
                "FeatureDownloader",
                "FeatureStemSeparation"
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "NikoMusicCore", "ProjectVaultRuntime", "FeatureArchiveBrowser", "FeatureAudioRecorder"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "ProjectVaultRuntimeTests",
            dependencies: ["ProjectVaultRuntime", "AppCore", "NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "AppUpdatesTests",
            dependencies: ["AppUpdates", "AppCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "NikoMusicCoreTests",
            dependencies: ["NikoMusicCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureBPMTapperTests",
            dependencies: ["FeatureBPMTapper"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureAudioConverterTests",
            dependencies: ["FeatureAudioConverter", "AppCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureAudioRecorderTests",
            dependencies: ["FeatureAudioRecorder", "AppCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureDownloaderTests",
            dependencies: ["FeatureDownloader", "AppCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureArchiveBrowserTests",
            dependencies: ["FeatureArchiveBrowser", "NikoMusicCore", "AppCore", "ProjectVaultRuntime"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FeatureStemSeparationTests",
            dependencies: ["FeatureStemSeparation", "AppCore"],
            resources: [
                .process("Fixtures")
            ],
            swiftSettings: strictSwiftSettings
        )
    ]
)
