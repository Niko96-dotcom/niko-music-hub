import Foundation
@testable import NikoMusicCore
import XCTest

final class SongCatalogSharingTests: XCTestCase {
    func testIdenticalDecodedSnapshotSharesThePreviousArray() throws {
        let previous = [song("A"), song("B")]
        let incoming = try JSONDecoder().decode([Song].self, from: JSONEncoder().encode(previous))
        let shared = SongCatalogDeduplicator.sharingUnchangedValues(incoming, from: previous)
        XCTAssertEqual(shared, incoming)
        previous.withUnsafeBufferPointer { old in
            shared.withUnsafeBufferPointer { new in XCTAssertEqual(old.baseAddress, new.baseAddress) }
        }
    }

    func testChangedMetadataFilesMembershipAndOrderFollowTheIncomingSnapshot() throws {
        let previous = [song("A"), song("B"), song("Removed")]
        var changed = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(previous[1]))
        changed.virtualTitle = "New title"
        changed.workflowStatus = .done
        changed.appNote = "New note"
        changed.previewCandidates = []
        changed.latestCPR = nil
        changed.projectVersions = []
        let same = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(previous[0]))
        let incoming = [changed, song("Added"), same]
        let shared = SongCatalogDeduplicator.sharingUnchangedValues(incoming, from: previous)
        XCTAssertEqual(shared, incoming)
        previous[0].previewCandidates.withUnsafeBufferPointer { old in
            shared[2].previewCandidates.withUnsafeBufferPointer { new in XCTAssertEqual(old.baseAddress, new.baseAddress) }
        }
        XCTAssertTrue(SongCatalogDeduplicator.sharingUnchangedValues([], from: previous).isEmpty)
    }

    private func song(_ name: String) -> Song {
        let folder = URL(fileURLWithPath: "/fixture-only/\(name)", isDirectory: true)
        let version = ProjectVersion(filePath: folder.appendingPathComponent("\(name).cpr"), fileName: "\(name).cpr", modifiedAt: .distantPast)
        let preview = PreviewCandidate(filePath: folder.appendingPathComponent("\(name).wav"), fileName: "\(name).wav", folderRole: .mixdown, modifiedAt: .distantPast, detectedRole: .mainMix)
        return Song(folderPath: folder, originalFolderName: name, displayTitle: name, projectVersions: [version], previewCandidates: [preview], latestCPR: version)
    }
}
