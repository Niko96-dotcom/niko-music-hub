import AppCore
import FeatureAudioConverter
import XCTest

final class AudioConverterFeatureTests: XCTestCase {
    func testRegistersWAVConverterMetadataAndCapabilities() throws {
        let feature = AudioConverterFeature()
        let registry = try ToolRegistry(features: [feature])

        let metadata = try XCTUnwrap(registry.metadata.first)
        XCTAssertEqual(metadata.id, "wav-converter")
        XCTAssertEqual(metadata.displayName, "WAV Converter")
        XCTAssertEqual(metadata.shortLabel, "WAV Converter")
        XCTAssertEqual(metadata.systemImage, "waveform")
        XCTAssertTrue(metadata.capabilities.contains(.producesFiles))
        XCTAssertTrue(metadata.capabilities.contains(.runsJobs))
    }
}
