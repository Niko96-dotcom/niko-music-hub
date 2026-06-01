import FeatureAudioConverter
import XCTest

final class AudioConverterHandoffTests: XCTestCase {
    func testVerifiedExistingWAVRowIsDragReady() throws {
        let outputURL = try makeExistingFile(named: "Ready.WAV")
        let row = makeRow(
            state: .verified,
            outputURL: outputURL
        )

        XCTAssertTrue(row.isDragReady())
        XCTAssertEqual(row.verifiedOutputURLForDrag(), outputURL)
    }

    func testFailedRowIsNotDragReady() throws {
        let outputURL = try makeExistingFile(named: "Failed.wav")
        let row = makeRow(
            state: .failed,
            outputURL: outputURL
        )

        XCTAssertFalse(row.isDragReady())
        XCTAssertNil(row.verifiedOutputURLForDrag())
    }

    func testSkippedRowIsNotDragReady() throws {
        let outputURL = try makeExistingFile(named: "Skipped.wav")
        let row = makeRow(
            state: .skipped,
            outputURL: outputURL
        )

        XCTAssertFalse(row.isDragReady())
        XCTAssertNil(row.verifiedOutputURLForDrag())
    }

    func testVerifiedMissingWAVRowIsNotDragReady() {
        let outputURL = temporaryDirectory().appendingPathComponent("Missing.wav")
        let row = makeRow(
            state: .verified,
            outputURL: outputURL
        )

        XCTAssertFalse(row.isDragReady())
        XCTAssertNil(row.verifiedOutputURLForDrag())
    }

    func testAudioConverterViewSourceContainsDragAndRevealHandoff() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )

        [
            "Drag WAV to Cubase",
            "NSItemProvider(contentsOf:",
            "revealInFinder"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing converter handoff source: \($0)")
        }
    }

    private func makeRow(
        state: AudioConverterRowState,
        outputURL: URL?
    ) -> AudioConverterRow {
        AudioConverterRow(
            sourceURL: temporaryDirectory().appendingPathComponent("Source.m4a"),
            sourceType: .m4a,
            plannedOutputName: "Source - 44100Hz 24bit.wav",
            state: state,
            statusText: state == .verified ? "Verified WAV ready" : "Not ready",
            progress: 1,
            outputURL: outputURL
        )
    }

    private func makeExistingFile(named name: String) throws -> URL {
        let url = temporaryDirectory().appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NikoMusicHubHandoffTests")
            .appendingPathComponent(UUID().uuidString)
    }
}
