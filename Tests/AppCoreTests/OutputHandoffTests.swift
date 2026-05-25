import AppCore
import XCTest

final class OutputHandoffTests: XCTestCase {
    func testAvailableExistingWAVIsDragReady() throws {
        let fileURL = try makeExistingFile(named: "loop.wav")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "wav-converter",
            status: .available
        )

        XCTAssertTrue(OutputHandoff.isRevealable(item))
        XCTAssertTrue(OutputHandoff.isDragReady(item))
        XCTAssertEqual(OutputHandoff.dragFileURL(for: item), fileURL)
    }

    func testMissingFileIsNotDragReady() {
        let fileURL = temporaryDirectory().appendingPathComponent("missing.wav")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "wav-converter",
            status: .available
        )

        XCTAssertFalse(OutputHandoff.isRevealable(item))
        XCTAssertFalse(OutputHandoff.isDragReady(item))
        XCTAssertNil(OutputHandoff.dragFileURL(for: item))
    }

    func testFailedItemIsNotRevealable() throws {
        let fileURL = try makeExistingFile(named: "failed.wav")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "wav-converter",
            status: .failed
        )

        XCTAssertFalse(OutputHandoff.isRevealable(item))
        XCTAssertFalse(OutputHandoff.isDragReady(item))
        XCTAssertNil(OutputHandoff.dragFileURL(for: item))
    }

    func testNonWAVAvailableItemIsNotDragReady() throws {
        let fileURL = try makeExistingFile(named: "source.m4a")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "wav-converter",
            status: .available
        )

        XCTAssertFalse(OutputHandoff.isRevealable(item))
        XCTAssertFalse(OutputHandoff.isDragReady(item))
        XCTAssertNil(OutputHandoff.dragFileURL(for: item))
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
            .appendingPathComponent("OutsideCubaseHubTests")
            .appendingPathComponent(UUID().uuidString)
    }
}
