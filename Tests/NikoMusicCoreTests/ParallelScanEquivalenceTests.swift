import XCTest
@testable import NikoMusicCore

/// A scan over many song folders runs them on several threads. The result must be exactly what the
/// one-folder-at-a-time walk returns: same songs, same order, same skipped entries and unusable ids.
/// Installing a race hook keeps the serial walk, which gives the reference result.
final class ParallelScanEquivalenceTests: XCTestCase {
    private func makeArchive(songCount: Int) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMH-ParallelScan-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<songCount {
            let name = ["Amber", "Neon", "Velvet", "Hollow"][index % 4] + " Song \(index)"
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
            if index % 9 != 0 {
                let project = folder.appendingPathComponent("\(name).cpr")
                try Data().write(to: project)
                try fm.setAttributes([.modificationDate: date.addingTimeInterval(Double(index) * 3_600)], ofItemAtPath: project.path)
            }
            for take in 1...(1 + index % 3) {
                let mix = folder.appendingPathComponent("Mixdown/\(name) v\(take) mix.wav")
                try Self.silentWAV(frames: 44_100 * (1 + take)).write(to: mix)
                try fm.setAttributes([.modificationDate: date.addingTimeInterval(Double(index * 10 + take))], ofItemAtPath: mix.path)
            }
            if index % 5 == 0 {
                try Data("notes \(index)".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            }
        }
        // Entries that are not song folders, an excluded-looking folder name and a symbolic link.
        try Data("x".utf8).write(to: root.appendingPathComponent("LOOSE_FILE.txt"))
        try Data().write(to: root.appendingPathComponent("Loose Project.cpr"))
        let outside = fm.temporaryDirectory.appendingPathComponent("NMH-ParallelScan-Outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Linked Song"), withDestinationURL: outside)
        addTeardownBlock { try? fm.removeItem(at: root); try? fm.removeItem(at: outside) }
        return root
    }

    private static func silentWAV(frames: Int) -> Data {
        var data = Data("RIFF".utf8)
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let payload = Data(count: frames * 2)
        data += le32(UInt32(36 + payload.count)) + Data("WAVEfmt ".utf8) + le32(16) + le16(1) + le16(1)
        data += le32(44_100) + le32(88_200) + le16(2) + le16(16) + Data("data".utf8) + le32(UInt32(payload.count)) + payload
        return data
    }

    func testParallelScanMatchesTheSerialWalk() throws {
        let root = try makeArchive(songCount: 150)

        var serial = MusicArchiveScanner()
        serial.raceHooks.songWalked = { _ in }
        let reference = try serial.scan(roots: [root])
        let parallel = try MusicArchiveScanner().scan(roots: [root])

        XCTAssertEqual(reference.songs.count, 150 + 1)
        XCTAssertEqual(parallel.songs, reference.songs)
        XCTAssertEqual(parallel.skippedEntries, reference.skippedEntries)
        XCTAssertEqual(parallel.unusableSongFolderIDs, reference.unusableSongFolderIDs)
        XCTAssertEqual(parallel.globalWarnings, reference.globalWarnings)
        XCTAssertTrue(parallel.skippedEntries.contains { $0.label == "Linked Song" })
        XCTAssertTrue(parallel.skippedEntries.contains { $0.label == "LOOSE_FILE.txt" })
    }

    func testParallelScanStopsWhenTheTaskIsCancelled() async throws {
        let root = try makeArchive(songCount: 300)
        let task = Task.detached { () throws -> ScanResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try MusicArchiveScanner().scan(roots: [root])
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled scan must not return a result")
        } catch is CancellationError {
            // Expected.
        }
    }
}
