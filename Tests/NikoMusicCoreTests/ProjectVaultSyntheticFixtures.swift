import Foundation

struct ProjectVaultSyntheticFixture {
    let root: URL
    let project: URL
    let existingMedia: URL
    let missingMedia: URL
    let alias: URL
    let symlink: URL
    let conflictCopy: URL
    let sparseFile: URL
}

enum ProjectVaultSyntheticFixtures {
    static func make(in parent: URL) throws -> ProjectVaultSyntheticFixture {
        let fm = FileManager.default
        let root = parent.appendingPathComponent("ProjectVaultSynthetic", isDirectory: true)
        let project = root.appendingPathComponent("Active/Nested/Synthetic Song", isDirectory: true)
        let audio = project.appendingPathComponent("Audio/Pool", isDirectory: true)
        let existingMedia = audio.appendingPathComponent("vocal take 01.wav")
        let missingMedia = audio.appendingPathComponent("missing guitar.wav")
        let alias = project.appendingPathComponent("Media Pool Alias.alias")
        let symlink = project.appendingPathComponent("Media Pool Link")
        let conflictCopy = root.appendingPathComponent(
            "Archive/Synthetic Song (Conflict Copy)/Synthetic Song.cpr"
        )
        let sparseFile = audio.appendingPathComponent("large sparse recording.wav")

        try fm.createDirectory(at: audio, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: conflictCopy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("synthetic CPR".utf8).write(to: project.appendingPathComponent("Synthetic Song.cpr"))
        try Data("media pool".utf8).write(to: project.appendingPathComponent("Pool.xml"))
        try Data("audio".utf8).write(to: existingMedia)
        try Data("conflict".utf8).write(to: conflictCopy)
        try fm.createSymbolicLink(at: symlink, withDestinationURL: audio)

        let bookmark = try audio.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmark, to: alias)

        try createSparseFile(at: sparseFile, logicalSize: 2_000_000_000)
        return ProjectVaultSyntheticFixture(
            root: root,
            project: project,
            existingMedia: existingMedia,
            missingMedia: missingMedia,
            alias: alias,
            symlink: symlink,
            conflictCopy: conflictCopy,
            sparseFile: sparseFile
        )
    }

    private static func createSparseFile(at url: URL, logicalSize: off_t) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(logicalSize))
    }
}
