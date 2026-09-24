import AppCore
import os
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

    func testDownloaderMP3IsHandoffReady() throws {
        let fileURL = try makeExistingFile(named: "track.mp3")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "downloader",
            status: .available
        )

        XCTAssertTrue(OutputHandoff.isRevealable(item))
        XCTAssertTrue(OutputHandoff.isDragReady(item))
        XCTAssertEqual(OutputHandoff.dragFileURL(for: item), fileURL)
    }

    func testDownloaderWAVIsRevealOpenAndDragReady() throws {
        let fileURL = try makeExistingFile(named: "downloaded.wav")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "downloader",
            status: .available
        )

        XCTAssertTrue(OutputHandoff.isRevealable(item))
        XCTAssertTrue(OutputHandoff.isOpenable(item))
        XCTAssertTrue(OutputHandoff.isDragReady(item))
        XCTAssertEqual(OutputHandoff.dragFileURL(for: item), fileURL)
    }

    func testDownloaderWAVDirectoryIsNotHandoffReady() throws {
        let directoryURL = temporaryDirectory().appendingPathComponent("directory.wav", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let item = OutputInboxItem(
            fileURL: directoryURL,
            sourceToolID: "downloader",
            status: .available
        )

        XCTAssertFalse(OutputHandoff.isRevealable(item))
        XCTAssertFalse(OutputHandoff.isOpenable(item))
        XCTAssertFalse(OutputHandoff.isDragReady(item))
        XCTAssertNil(OutputHandoff.dragFileURL(for: item))
    }

    func testDownloaderWEBMIsRevealOnly() throws {
        let fileURL = try makeExistingFile(named: "clip.webm")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "downloader",
            status: .available
        )

        XCTAssertTrue(OutputHandoff.isRevealable(item))
        XCTAssertFalse(OutputHandoff.isDragReady(item))
        XCTAssertNil(OutputHandoff.dragFileURL(for: item))
    }

    func testNonWAVConverterItemIsNotDragReady() throws {
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

    func testDragItemProviderPreservesFilename() throws {
        let fileURL = try makeExistingFile(named: "Some Take - 44100Hz 24bit.wav")
        let provider = OutputHandoff.dragItemProvider(for: fileURL)

        XCTAssertEqual(provider.suggestedName, "Some Take - 44100Hz 24bit.wav")
        XCTAssertTrue(
            provider.registeredTypeIdentifiers.contains("public.file-url"),
            "expected public.file-url in \(provider.registeredTypeIdentifiers)"
        )

        let expectation = self.expectation(description: "load dragged file URL")
        let loaded = OSAllocatedUnfairLock<String?>(initialState: nil)
        provider.loadObject(ofClass: NSURL.self) { nsURL, _ in
            let name = ((nsURL as? NSURL) as URL?)?.lastPathComponent
            loaded.withLock { $0 = name }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        let loadedLastPathComponent = loaded.withLock { $0 }
        XCTAssertEqual(loadedLastPathComponent, "Some Take - 44100Hz 24bit.wav")
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
