@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The intelligence owner on its own: a refresh applies its hints, a dismissal outlives every
/// later apply until the next scan, and a root change stops the refresh and clears everything.
@MainActor
final class ArchiveIntelligenceModelTests: XCTestCase {
    private let jamie = Collaborator(id: "jamie", displayName: "Jamie Rivera")

    private func song(_ name: String) -> Song {
        Song(folderPath: URL(fileURLWithPath: "/tmp/intelligence/\(name)", isDirectory: true),
             originalFolderName: name, displayTitle: name)
    }

    private func suggestion(for song: Song) -> CollaboratorSuggestion {
        CollaboratorSuggestion(songID: song.id, songTitle: song.effectiveDisplayTitle,
                               suggestedCollaboratorID: jamie.id, suggestedName: jamie.displayName, reason: "test")
    }

    func testAnImmediateRefreshAppliesTheHintsOfItsSnapshot() async {
        let model = ArchiveIntelligenceModel()

        model.refresh(songs: [song("Jamie Rivera Session")], collaborators: [jamie], immediate: true)
        await model.refreshTask?.value

        XCTAssertEqual(model.pendingCollaboratorSuggestions.map(\.suggestedCollaboratorID), [jamie.id])
        XCTAssertNotNil(model.missingAudioReport)
    }

    func testADismissalOutlivesLaterAppliesUntilTheNextScan() {
        let model = ArchiveIntelligenceModel()
        let row = suggestion(for: song("Session"))
        model.apply(suggestions: [row], duplicates: [], missing: nil)

        model.dismiss(row)
        model.apply(suggestions: [row], duplicates: [], missing: nil)
        XCTAssertTrue(model.pendingCollaboratorSuggestions.isEmpty, "an apply never reinserts a dismissed row")

        model.endDismissalsForNewScan()
        model.apply(suggestions: [row], duplicates: [], missing: nil)
        XCTAssertEqual(model.pendingCollaboratorSuggestions.map(\.id), [row.id])
    }

    func testRemovingAnAcceptedRowKeepsItEligibleLater() {
        let model = ArchiveIntelligenceModel()
        let row = suggestion(for: song("Session"))
        model.apply(suggestions: [row], duplicates: [], missing: nil)

        model.removeSuggestion(row)

        XCTAssertTrue(model.pendingCollaboratorSuggestions.isEmpty)
        XCTAssertTrue(model.dismissedCollaboratorSuggestionIDs.isEmpty, "only a dismissal hides a row until the next scan")
    }

    func testARootChangeStopsTheRefreshAndClearsEverything() async {
        let model = ArchiveIntelligenceModel()
        let row = suggestion(for: song("Session"))
        model.apply(suggestions: [row], duplicates: [], missing: MissingAudioReport(songs: []))
        model.dismiss(suggestion(for: song("Other")))
        model.refresh(songs: [song("Jamie Rivera Session")], collaborators: [jamie], immediate: false)

        model.clearForRootChange()
        await model.refreshTask?.value

        XCTAssertTrue(model.pendingCollaboratorSuggestions.isEmpty, "the cancelled refresh applies nothing")
        XCTAssertTrue(model.dismissedCollaboratorSuggestionIDs.isEmpty)
        XCTAssertTrue(model.duplicateSongHints.isEmpty)
        XCTAssertNil(model.missingAudioReport)
    }
}
