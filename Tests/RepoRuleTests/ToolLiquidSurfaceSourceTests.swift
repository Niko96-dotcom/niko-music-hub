import XCTest

/// Tool pages build on the shared surfaces (`hubCard`, `ToolHeaderBlock`, `HubJobProgressRow`, the
/// shared handoff) and define no glass formula of their own.
/// AGENTS.md row "Design contract"; docs/design-contract.md §4 and §6.
final class ToolLiquidSurfaceSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Shared tool surfaces",
        why: "Local copies of a surface or a glass formula drift from the design contract one tool at a time",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md §4 and §6",
        fix: "Use the shared component (hubCard, ToolHeaderBlock, HubWaveformSurface, HubJobProgressRow) instead of a local formula"
    )

    private static let localGlassFormulas = [
        ".thinMaterial",
        "meterGradient",
        "Color.primary.opacity(0.02)",
        "Color.primary.opacity(0.03)",
        "Color.primary.opacity(0.04)",
        ".fill(isSelected ? HubDesignSystem.Colors.accentTint",
    ]

    func testBPMTapperUsesSharedLiquidSurfaces() {
        Self.rule.expect(
            "Sources/FeatureBPMTapper/BPMTapperView.swift",
            contains: ["hubCard", "ToolHeaderBlock", "tapSurfaceFocused", "viewModel.recordTap()", "viewModel.resetTaps()", "viewModel.clearHistory()"],
            lacks: Self.localGlassFormulas
        )
    }

    func testRecorderUsesSharedLiquidMeterAndStateSurfaces() {
        Self.rule.expect(
            "Sources/FeatureAudioRecorder/AudioRecorderView.swift",
            contains: [
                "HubWaveformSurface", "HubMediaSurfaceFixtures.meterPeaks", "hubCard", "ToolHeaderBlock",
                "viewModel.startRecording()", "viewModel.stopRecording()", "HubStepSlider(",
                "SystemPrivacySettings.openSystemAudioRecordingSettings()",
            ],
            lacks: Self.localGlassFormulas
        )
    }

    func testConverterUsesSharedLiquidDropBatchAndHandoffSurfaces() {
        Self.rule.expect(
            "Sources/FeatureAudioConverter/AudioConverterView.swift",
            contains: [
                "hubCard", "ToolHeaderBlock", "onDrop", "OutputHandoff.dragItemProvider(for:", "viewModel.addFileURLs",
                "viewModel.startConversion()", "Reveal", "hubDragAffordance",
            ],
            lacks: Self.localGlassFormulas
        )
    }

    func testDownloaderUsesSharedLiquidURLFormatProgressAndHandoffSurfaces() {
        Self.rule.expect(
            "Sources/FeatureDownloader/DownloaderView.swift",
            contains: [
                "hubCard", "ToolHeaderBlock", "DownloaderCopy.trustNotice", "viewModel.startDownload()",
                "viewModel.retryAfterFailure()", "Download as", "HubJobProgressRow(",
                "fraction: viewModel.showsDeterminateProgress ? viewModel.progress : nil",
            ],
            lacks: Self.localGlassFormulas
        )
    }
}
