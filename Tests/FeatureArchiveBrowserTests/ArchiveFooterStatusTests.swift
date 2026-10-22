@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveFooterStatusTests: XCTestCase {
    private typealias Warning = ArchiveFooterStatus.Warning

    // MARK: - Precedence

    func testSecondMessageWinsUnlessBackgroundMeetsAVaultHold() {
        let sources: [ArchiveFooterStatus.Source] = [.action, .background, .projectVault]
        for first in sources {
            for second in sources {
                var footer = ArchiveFooterStatus()
                footer.show("first", from: first)
                footer.show("second", from: second)
                let expected = first == .projectVault && second == .background ? "first" : "second"
                XCTAssertEqual(footer.text, expected, "\(first) then \(second)")
            }
        }
    }

    func testActionMessageReleasesTheVaultHold() {
        var footer = ArchiveFooterStatus()
        footer.show("Archiving…", from: .projectVault)
        footer.show("Exported.", from: .action)
        footer.show("Scanned 9 songs.", from: .background)
        XCTAssertEqual(footer.text, "Scanned 9 songs.")
    }

    func testClearingAVaultMessageKeepsTheHold() {
        var footer = ArchiveFooterStatus()
        footer.show("Archiving…", from: .projectVault)
        footer.show(nil, from: .projectVault)
        footer.show("Scanned 9 songs.", from: .background)
        XCTAssertNil(footer.text)
    }

    // MARK: - Composition

    func testTextJoinsMessageAndWarningWithOneSpace() {
        var footer = ArchiveFooterStatus()
        XCTAssertNil(footer.text)
        footer.show("Scanned 9 songs.", from: .action)
        XCTAssertEqual(footer.text, "Scanned 9 songs.")
        footer.raise(Warning("Collaborators could not be saved."))
        XCTAssertEqual(footer.text, "Scanned 9 songs. Collaborators could not be saved.")
        footer.show(nil, from: .action)
        XCTAssertEqual(footer.text, "Collaborators could not be saved.")
        footer.show("", from: .action)
        XCTAssertEqual(footer.text, "Collaborators could not be saved.")
        footer.clearWarning()
        XCTAssertEqual(footer.text, "")
    }

    // MARK: - Warnings

    func testNewWarningReplacesTheOldOne() {
        var footer = ArchiveFooterStatus()
        footer.raise(.rootAccess(rootName: "Archive A"))
        footer.raise(.projectVaultUnreadable(recordsOnly: false))
        XCTAssertEqual(footer.warning, .projectVaultUnreadable(recordsOnly: false))
    }

    func testResolveClearsOnlyAWarningOfThatKind() {
        var footer = ArchiveFooterStatus()
        footer.raise(.rootAccess(rootName: "Archive A"))
        footer.resolve(.settings)
        XCTAssertEqual(footer.warning?.kind, .rootAccess)
        footer.resolve(.rootAccess)
        XCTAssertNil(footer.warning)
    }

    func testWithdrawClearsOnlyTheExactMessageAndKeepsTheVaultHold() {
        var footer = ArchiveFooterStatus()
        footer.show("Waiting for upload.", from: .projectVault)
        footer.withdraw("Something else.")
        XCTAssertEqual(footer.message, "Waiting for upload.")
        footer.withdraw("Waiting for upload.")
        XCTAssertNil(footer.message)
        footer.show("Scanned 9 songs.", from: .background)
        XCTAssertNil(footer.message, "the Vault still holds the footer after a withdraw")
    }

    // MARK: - Warning sentences and kinds (byte-for-byte as before the footer type)

    func testRootAccessSentence() {
        XCTAssertEqual(
            Warning.rootAccess(rootName: "Second"),
            Warning(kind: .rootAccess, text: "Archive root access could not be restored: Second.")
        )
    }

    func testSettingsSentences() {
        let disk = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full."])
        XCTAssertEqual(
            Warning.settingsLoadFailed(disk),
            Warning(kind: .settings, text: "Archive settings could not be loaded: disk full.")
        )
        XCTAssertEqual(
            Warning.settingsSaveFailed(disk),
            Warning(kind: .settings, text: "Archive settings could not be saved: disk full.")
        )
        let undecodable = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(
            Warning.settingsSaveFailed(undecodable),
            Warning(kind: .settings, text: ArchiveWriteGuardError.settingsUnreadable.localizedDescription)
        )
    }

    func testArchiveWriteRefusedIsASettingsWarningOnlyForUnreadableSettings() {
        XCTAssertEqual(
            Warning.archiveWriteRefused(ArchiveWriteGuardError.settingsUnreadable),
            Warning(kind: .settings, text: ArchiveWriteGuardError.settingsUnreadable.localizedDescription)
        )
        let other = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bookmark refused."])
        XCTAssertEqual(Warning.archiveWriteRefused(other), Warning(kind: .other, text: "Bookmark refused."))
    }

    func testProjectVaultReadSentences() {
        XCTAssertEqual(
            Warning.projectVaultUnreadable(recordsOnly: false),
            Warning(kind: .projectVaultRead, text: "Project Vault status couldn't be read. Nothing was changed.")
        )
        XCTAssertEqual(
            Warning.projectVaultUnreadable(recordsOnly: true),
            Warning(kind: .projectVaultRead, text: "Some Project Vault records couldn't be read. They were left as they are.")
        )
    }

    /// A repair replaces exactly the warnings `SongMetadataIntegrityCopy` calls
    /// integrity warnings; "can't be saved" stays an ordinary warning.
    func testPlainWarningsRecognizeSongDetailsSentences() {
        XCTAssertEqual(Warning(SongMetadataIntegrityCopy.corrupt(["Neon Hook"])).kind, .songDetails)
        XCTAssertEqual(Warning(SongMetadataIntegrityCopy.unverified("Neon Hook")).kind, .songDetails)
        XCTAssertEqual(Warning(SongMetadataIntegrityCopy.loadFailedEditsBlocked).kind, .songDetails)
        XCTAssertEqual(Warning(SongMetadataIntegrityCopy.loadFailedScan).kind, .songDetails)
        XCTAssertEqual(Warning(SongMetadataIntegrityCopy.storageUnavailable).kind, .other)
        XCTAssertEqual(Warning("Collaborators could not be saved.").kind, .other)
    }

    // MARK: - Same footer text as the view model's former funnel

    /// The four setters and the composition the view model used before this
    /// type existed, kept here as the reference the migration must match.
    private struct FormerFunnel {
        var base: String?
        var warning: String?
        var vaultOwns = false
        var text: String?

        mutating func setStatus(_ message: String?) {
            vaultOwns = false
            base = message
            text = combined()
        }

        mutating func setVaultStatus(_ message: String?) {
            vaultOwns = true
            base = message
            text = combined()
        }

        mutating func setBackgroundStatus(_ message: String?) {
            guard !vaultOwns else { return }
            setStatus(message)
        }

        mutating func recordWarning(_ newWarning: String) {
            warning = newWarning
            text = combined()
        }

        private func combined() -> String? {
            guard let warning else { return base }
            guard let base, !base.isEmpty else { return warning }
            return "\(base) \(warning)"
        }
    }

    func testRandomCallSequencesMatchTheFormerFunnel() {
        let messages: [String?] = [nil, "", "Scanned 9 songs.", "Archiving “Neon Hook”…", "Exported."]
        let warnings = ["Archive settings could not be saved: disk full.", "Collaborators could not be saved."]
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<500 {
            var former = FormerFunnel()
            var footer = ArchiveFooterStatus()
            for _ in 0..<12 {
                let message = messages[next(messages.count)]
                switch next(4) {
                case 0:
                    former.setStatus(message)
                    footer.show(message, from: .action)
                case 1:
                    former.setVaultStatus(message)
                    footer.show(message, from: .projectVault)
                case 2:
                    former.setBackgroundStatus(message)
                    footer.show(message, from: .background)
                default:
                    let warning = warnings[next(warnings.count)]
                    former.recordWarning(warning)
                    footer.raise(Warning(warning))
                }
                XCTAssertEqual(footer.text, former.text)
                XCTAssertEqual(footer.message, former.base)
            }
        }
    }
}
