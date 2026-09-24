import FeatureStemSeparation
import Foundation
import Testing

struct StemOutputScannerTests {

    private let scanner = StemOutputScanner()

    @Test
    func scan_normalizesFourStemOutputs() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav", "drums.wav", "bass.wav", "other.wav"])
        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .success(let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(stems.map(\.role) == [.bass, .drums, .other, .vocals])
    }

    @Test
    func scan_reportsMissingStems() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav", "drums.wav", "bass.wav"])
        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("Missing stems"))
        #expect(message.contains("Other"))
    }

    @Test
    func scan_reportsDuplicateRole() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav", "vocals_2.wav"])
        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("Duplicate output"))
    }

    @Test
    func scan_rejectsFilesEscapingFolder() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav"])
        let symlinkURL = folder.appendingPathComponent("escape.wav")
        try? FileManager.default.removeItem(at: symlinkURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()))

        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("escapes"))
    }

    @Test
    func scan_rejectsSymlinkIntoSiblingFolderSharingThePrefix() throws {
        // "/x/job-other/vocals.wav" starts with "/x/job" but is outside "/x/job".
        let folder = try createTempFolder(withFiles: ["drums.wav", "bass.wav", "other.wav"])
        let sibling = URL(fileURLWithPath: folder.path + "-other", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        let outsideVocals = sibling.appendingPathComponent("vocals.wav")
        FileManager.default.createFile(atPath: outsideVocals.path, contents: Data("stem".utf8))
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("vocals.wav"),
            withDestinationURL: outsideVocals
        )

        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("escapes"))
    }

    @Test
    func scan_ignoresSubdirectoriesAndUnrelatedFiles() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav", "drums.wav", "bass.wav", "other.wav", "readme.txt"])
        let subFolder = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.fast4.expectedStemRoles)
        guard case .success(let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(stems.count == 4)
    }

    @Test
    func scan_supportsExperimentalSixStemRoles() throws {
        let folder = try createTempFolder(withFiles: ["vocals.wav", "drums.wav", "bass.wav", "other.wav", "guitar.wav", "piano.wav"])
        let result = scanner.scan(outputFolderURL: folder, expectedRoles: StemSeparationPreset.experimental6.expectedStemRoles)
        guard case .success(let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        let roles = Set(stems.map(\.role))
        #expect(roles == [.vocals, .drums, .bass, .other, .guitar, .piano])
    }
}

private func createTempFolder(withFiles filenames: [String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in filenames {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("stem".utf8))
    }
    return folder
}
