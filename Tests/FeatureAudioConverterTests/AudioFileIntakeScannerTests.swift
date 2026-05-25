import FeatureAudioConverter
import XCTest

final class AudioFileIntakeScannerTests: XCTestCase {
    func testAcceptsSupportedFileExtensions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try ["m4a", "mp3", "wav", "aiff", "aif", "flac"].map { fileExtension in
            try makeFile(named: "Source.\(fileExtension)", in: directory)
        }
        let scanner = AudioFileIntakeScanner()

        let result = try scanner.scan(urls)

        XCTAssertEqual(result.supportedFiles.map(\.url), urls)
        XCTAssertEqual(result.supportedFiles.map(\.sourceType), [.m4a, .mp3, .wav, .aiff, .aiff, .flac])
        XCTAssertTrue(result.unsupportedFiles.isEmpty)
        XCTAssertTrue(result.notices.isEmpty)
    }

    func testUnsupportedFilesBecomeUnsupportedRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let textFile = try makeFile(named: "Notes.txt", in: directory)
        let imageFile = try makeFile(named: "Cover.png", in: directory)
        let scanner = AudioFileIntakeScanner()

        let result = try scanner.scan([textFile, imageFile])

        XCTAssertTrue(result.supportedFiles.isEmpty)
        XCTAssertEqual(result.unsupportedFiles.map(\.url), [textFile, imageFile])
    }

    func testDroppedFolderScansTopLevelOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let topLevelFile = try makeFile(named: "Top Level.m4a", in: directory)
        let unsupportedFile = try makeFile(named: "Readme.md", in: directory)
        let nestedFolder = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        _ = try makeFile(named: "Nested.flac", in: nestedFolder)
        let scanner = AudioFileIntakeScanner()

        let result = try scanner.scan([directory])

        XCTAssertEqual(result.supportedFiles.map { $0.url.lastPathComponent }, [topLevelFile.lastPathComponent])
        XCTAssertEqual(result.unsupportedFiles.map { $0.url.lastPathComponent }, [unsupportedFile.lastPathComponent])
        XCTAssertEqual(result.notices, [.subfoldersIgnored(folderURL: directory, count: 1)])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubIntakeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try Data("fixture".utf8).write(to: url)
        return url
    }
}
