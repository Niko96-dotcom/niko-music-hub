import AppCore
import FeatureAudioConverter
import XCTest

final class AudioConverterFeatureTests: XCTestCase {
    func testRegistersWAVConverterMetadataAndSection() throws {
        let feature = AudioConverterFeature()
        let registry = try ToolRegistry(features: [feature])

        let metadata = try XCTUnwrap(registry.metadata.first)
        XCTAssertEqual(metadata.id, "wav-converter")
        XCTAssertEqual(metadata.displayName, "WAV Converter")
        XCTAssertEqual(metadata.shortLabel, "WAV Converter")
        XCTAssertEqual(metadata.systemImage, "waveform")
        XCTAssertEqual(metadata.section, .production)
        XCTAssertTrue(metadata.handlesEscape)
    }

    /// The converter's row in the jobs strip: its text, its Cancel help and what Esc
    /// and ⌘. cancel it as (moved from `ShellJobStatusCenterTests`).
    func testConverterJobRowDescribesItself() throws {
        XCTAssertNil(ConverterJobReporting.status(isConverting: false, filename: "Loop.m4a", percent: 0.2))

        let converting = try XCTUnwrap(
            ConverterJobReporting.status(isConverting: true, filename: "Loop.m4a", percent: 0.5)
        )
        XCTAssertEqual(converting.title, "Loop.m4a")
        XCTAssertEqual(converting.displayLine, "Converting “Loop.m4a” · 50%")
        XCTAssertEqual(converting.cancelActionID, ShellJobExtraSourceID.converter)
        XCTAssertEqual(converting.sourceToolID, AudioConverterFeature().metadata.id)
        XCTAssertEqual(converting.cancelTarget, .conversion)
        XCTAssertEqual(converting.cancelHelp, "Stops converting now and skips the rest. Verified WAV files are kept.")

        let fallback = try XCTUnwrap(ConverterJobReporting.status(isConverting: true, filename: nil, percent: 0))
        XCTAssertEqual(fallback.title, "WAV Converter")
        XCTAssertEqual(fallback.displayLine, "WAV Converter")
        XCTAssertEqual(fallback.cancelTarget, .conversion)
        XCTAssertEqual(ConverterJobReporting.status(isConverting: true, filename: "", percent: 0)?.displayLine, "WAV Converter")
    }
}
