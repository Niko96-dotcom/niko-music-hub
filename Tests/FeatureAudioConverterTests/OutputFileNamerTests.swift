import FeatureAudioConverter
import XCTest

final class OutputFileNamerTests: XCTestCase {
    func testAppendsPresetSuffix() {
        let namer = OutputFileNamer()
        let outputDirectory = URL(fileURLWithPath: "/tmp/outside-cubase")
        let sourceURL = URL(fileURLWithPath: "/tmp/sources/Kick Loop.m4a")

        let outputURL = namer.plannedOutputURL(
            for: outputDirectory,
            sourceURL: sourceURL,
            preset: .cubaseDefault,
            existingFileExists: { _ in false }
        )

        XCTAssertEqual(outputURL.lastPathComponent, "Kick Loop - 44100Hz 24bit.wav")
    }

    func testAppendsCounterWhenFileExists() {
        let namer = OutputFileNamer()
        let outputDirectory = URL(fileURLWithPath: "/tmp/outside-cubase")
        let sourceURL = URL(fileURLWithPath: "/tmp/sources/Kick Loop.m4a")
        let existingFiles: Set<String> = [
            "/tmp/outside-cubase/Kick Loop - 44100Hz 24bit.wav",
            "/tmp/outside-cubase/Kick Loop - 44100Hz 24bit 2.wav"
        ]

        let outputURL = namer.plannedOutputURL(
            for: outputDirectory,
            sourceURL: sourceURL,
            preset: .cubaseDefault,
            existingFileExists: { existingFiles.contains($0.path) }
        )

        XCTAssertEqual(outputURL.lastPathComponent, "Kick Loop - 44100Hz 24bit 3.wav")
    }

    func testLongMultibyteStemLeavesRoomForTemporaryName() {
        let namer = OutputFileNamer()
        let outputDirectory = URL(fileURLWithPath: "/tmp/outside-cubase")
        let longTitle = String(repeating: "音", count: 80)
        let sourceURL = URL(fileURLWithPath: "/tmp/sources/\(longTitle).m4a")

        let outputURL = namer.plannedOutputURL(
            for: outputDirectory,
            sourceURL: sourceURL,
            preset: .cubaseDefault,
            existingFileExists: { _ in false }
        )

        let name = outputURL.lastPathComponent
        XCTAssertTrue(name.hasPrefix("音"))
        XCTAssertTrue(name.hasSuffix(" - 44100Hz 24bit.wav"))
        // The converters write "<stem>.<UUID>.tmp.wav" next to the final file.
        let temporaryName = "\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp.wav"
        XCTAssertLessThanOrEqual(temporaryName.utf8.count, 255)
    }
}
