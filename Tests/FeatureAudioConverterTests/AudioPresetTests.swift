import FeatureAudioConverter
import XCTest

final class AudioPresetTests: XCTestCase {
    func testCubaseDefaultPreservesMonoStereo() {
        XCTAssertEqual(AudioPreset.cubaseDefault.sampleRate, 44100)
        XCTAssertEqual(AudioPreset.cubaseDefault.bitDepth, 24)
        XCTAssertEqual(AudioPreset.cubaseDefault.channelCount, 2)
        XCTAssertEqual(AudioPreset.cubaseDefault.channelMode, .preserveMonoStereo)
    }
}
