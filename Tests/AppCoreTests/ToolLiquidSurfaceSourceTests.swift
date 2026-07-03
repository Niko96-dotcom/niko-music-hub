import XCTest

final class ToolLiquidSurfaceSourceTests: XCTestCase {
    func testBPMTapperUsesSharedLiquidSurfaces() throws {
        let source = try featureSource("FeatureBPMTapper/BPMTapperView.swift")

        [
            "hubCard",
            "ToolHeaderBlock",
            "tapSurfaceFocused",
            "viewModel.recordTap()",
            "viewModel.resetTaps()",
            "viewModel.clearHistory()",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing BPM Liquid source: \(required)")
        }

        assertNoLocalGlassFormulas(in: source, feature: "BPM Tapper")
    }

    func testRecorderUsesSharedLiquidMeterAndStateSurfaces() throws {
        let source = try featureSource("FeatureAudioRecorder/AudioRecorderView.swift")

        [
            "HubWaveformSurface",
            "HubMediaSurfaceFixtures.meterPeaks",
            "hubCard",
            "ToolHeaderBlock",
            "viewModel.startRecording()",
            "viewModel.stopRecording()",
            "HubChoiceChips(\"Max Duration\"",
            "SystemPrivacySettings.openSystemAudioRecordingSettings()",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing recorder Liquid source: \(required)")
        }

        XCTAssertFalse(source.contains("meterGradient"), "Recorder should use HubWaveformSurface instead of local meter gradients.")
        assertNoLocalGlassFormulas(in: source, feature: "Recorder")
    }

    func testConverterUsesSharedLiquidDropBatchAndHandoffSurfaces() throws {
        let source = try featureSource("FeatureAudioConverter/AudioConverterView.swift")

        [
            "hubCard",
            "ToolHeaderBlock",
            "onDrop",
            "NSItemProvider(contentsOf:",
            "viewModel.addFileURLs",
            "viewModel.startConversion()",
            "Reveal",
            "hubDragAffordance",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing converter Liquid source: \(required)")
        }

        assertNoLocalGlassFormulas(in: source, feature: "Converter")
    }

    func testDownloaderUsesSharedLiquidURLFormatProgressAndHandoffSurfaces() throws {
        let source = try featureSource("FeatureDownloader/DownloaderView.swift")

        [
            "hubCard",
            "ToolHeaderBlock",
            "DownloaderCopy.trustNotice",
            "viewModel.startDownload()",
            "viewModel.retryAfterFailure()",
            "Download as:",
            "ProgressView(value: viewModel.progress)",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing downloader Liquid source: \(required)")
        }

        assertNoLocalGlassFormulas(in: source, feature: "Downloader")
    }

    private func assertNoLocalGlassFormulas(in source: String, feature: String) {
        [
            ".thinMaterial",
            "meterGradient",
            "Color.primary.opacity(0.02)",
            "Color.primary.opacity(0.03)",
            "Color.primary.opacity(0.04)",
            ".fill(isSelected ? HubDesignSystem.Colors.accentTint",
        ].forEach { forbidden in
            XCTAssertFalse(source.contains(forbidden), "\(feature) still defines local glass formula: \(forbidden)")
        }
    }

    private func featureSource(_ path: String) throws -> String {
        try String(
            contentsOfFile: "Sources/\(path)",
            encoding: .utf8
        )
    }
}
