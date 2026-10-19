import XCTest
@testable import NikoMusicCore

/// The recent-first shelves sort (index, date) pairs instead of `(Song, Date)` tuples, and collaborator
/// suggestions fold each collaborator's name once. Both must return what the straightforward versions
/// return, ties and ignored songs included.
final class ArchiveBrowseSortEquivalenceTests: XCTestCase {
    private func makeSongs(count: Int) -> [Song] {
        var generator = SeededGenerator(seed: 42)
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        return (0..<count).map { index in
            let folder = URL(fileURLWithPath: "/tmp/sort-\(index)", isDirectory: true)
            // Few distinct dates, so many songs tie; some songs have no CPR or no mixdown at all.
            let day = Double(Int.random(in: 0..<12, using: &generator)) * 86_400
            let versions = index % 7 == 0 ? [] : [
                ProjectVersion(filePath: folder.appendingPathComponent("a.cpr"), fileName: "a.cpr", modifiedAt: base.addingTimeInterval(day))
            ]
            let previews = index % 5 == 0 ? [] : [
                PreviewCandidate(filePath: folder.appendingPathComponent("Mixdown/a.wav"), fileName: "a.wav",
                                 folderRole: .mixdown, modifiedAt: base.addingTimeInterval(day * 2), detectedRole: .mainMix)
            ]
            return Song(folderPath: folder, originalFolderName: "Song \(index)", displayTitle: "Song \(index)",
                        projectVersions: versions, previewCandidates: previews,
                        latestCPR: versions.first)
        }
    }

    func testRecentShelvesMatchTheTupleSort() {
        let songs = makeSongs(count: 600)
        let cprReference = songs
            .compactMap { song -> (Song, Date)? in ArchiveShelfRanker.latestCPRActivity(for: song).map { (song, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let bounceReference = songs
            .compactMap { song -> (Song, Date)? in ArchiveShelfRanker.latestMixdownActivity(for: song).map { (song, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        XCTAssertEqual(ArchiveShelfRanker.recentCPRActivity(songs).map(\.id), cprReference.map(\.id))
        XCTAssertEqual(ArchiveShelfRanker.recentlyBounced(songs).map(\.id), bounceReference.map(\.id))
        XCTAssertEqual(ArchiveBrowseSortMode.sort(songs, mode: .recentCPR).count, songs.count)
    }

    func testQuietSongsAndTheirCountMatchTheTupleSort() {
        var songs = makeSongs(count: 600)
        let statuses: [ProjectWorkflowStatus?] = [nil, .done] + ProjectWorkflowStatus.allCases.filter { $0 != .done }.map { Optional($0) }
        for index in songs.indices { songs[index].workflowStatus = statuses[index % statuses.count] }
        let now = Date(timeIntervalSince1970: 1_600_000_000 + 90 * 86_400)
        let cutoff = now.addingTimeInterval(-TimeInterval(ArchiveShelfRanker.quietSongThresholdDays) * 86_400)
        let reference = songs
            .compactMap { song -> (Song, Date)? in
                guard let status = song.workflowStatus, status != .done else { return nil }
                guard let latest = ArchiveShelfRanker.latestCPRActivity(for: song), latest <= cutoff else { return nil }
                return (song, latest)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        XCTAssertFalse(reference.isEmpty)
        XCTAssertEqual(ArchiveShelfRanker.quietSongs(songs, now: now).map(\.id), reference.map(\.id))
        XCTAssertEqual(ArchiveShelfRanker.quietSongCount(songs, now: now), reference.count)
    }

    func testCollaboratorSuggestionsMatchTheUnhoistedLoop() {
        let collaborators = ["Lena", "Max Muster", "Jo", "Ünal Çelik", "Mira"].map {
            Collaborator(id: "id-\($0)", displayName: $0, updatedAt: Date(timeIntervalSince1970: 1_600_000_000))
        }
        let names = ["Amber Lena Hook", "Max Muster demo", "unal celik session", "Mira and Lena", "Plain Song", "Jo only"]
        var songs = names.enumerated().map { index, name in
            Song(folderPath: URL(fileURLWithPath: "/tmp/collab-\(index)", isDirectory: true),
                 originalFolderName: name, displayTitle: name)
        }
        songs[3].collaboratorIDs = ["id-Lena"]
        songs[4].isIgnored = true
        let suggestions = ArchiveIntelligence.collaboratorSuggestions(songs: songs, collaborators: collaborators)
        // Reference: tokenize the collaborator inside the song loop, exactly as before the change.
        var expected: [String] = []
        for song in songs where !song.isIgnored {
            let folderTokens = Self.tokens(song.originalFolderName)
            for collaborator in collaborators where !song.collaboratorIDs.contains(collaborator.id) {
                let nameTokens = Self.tokens(collaborator.displayName)
                if !nameTokens.isEmpty, nameTokens.allSatisfy({ folderTokens.contains($0) }) {
                    expected.append(song.id + "|" + collaborator.id)
                }
            }
        }
        XCTAssertEqual(suggestions.map { $0.songID + "|" + $0.suggestedCollaboratorID }, expected)
        XCTAssertFalse(expected.isEmpty)
    }

    private static func tokens(_ value: String) -> Set<String> {
        func normalize(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        }
        return Set(value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { normalize(String($0)) }.filter { $0.count >= 3 })
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
