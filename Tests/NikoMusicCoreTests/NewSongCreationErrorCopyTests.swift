import XCTest
@testable import NikoMusicCore

final class NewSongCreationErrorCopyTests: XCTestCase {
    func testEveryCreationErrorHasLocalizedDescription() {
        let name = "Neon Hook"
        let cases: [NewSongFolderCreator.CreationError] = [
            .emptyName,
            .invalidName,
            .folderExists,
            .archiveRootIsReadOnly,
            .destinationUnavailable,
            .templateMissing,
            .templateUnreadable,
            .templateOverlap,
            .templateConflict("notes.txt"),
            .templateCopyFailed,
            .stagingFailed,
            .stagingValidationFailed,
            .finalizationFailed,
        ]
        for error in cases {
            let description = NewSongCreationErrorCopy.errorDescription(for: error, name: name)
            XCTAssertFalse(description.isEmpty, "\(error) has an empty message")
            XCTAssertFalse(description.contains("!"), "\(error) message contains an exclamation mark")
        }
        XCTAssertEqual(
            NewSongCreationErrorCopy.errorDescription(for: .folderExists, name: name),
            "A folder named “Neon Hook” already exists in New Song Drafts. Choose another name."
        )
        XCTAssertEqual(
            NewSongCreationErrorCopy.errorDescription(for: .archiveRootIsReadOnly, name: name),
            "The draft was not created because the output folder is inside an archive root. Choose another folder in Settings > Output, then try again."
        )
        // LocalizedError conformance surfaces the same copy table.
        XCTAssertEqual(
            (NewSongFolderCreator.CreationError.invalidName as Error).localizedDescription,
            "Use a plain folder name without slashes or parent-folder segments."
        )
        XCTAssertEqual(
            (NewSongFolderCreator.CreationError.emptyName as Error).localizedDescription,
            "Enter a song folder name."
        )
    }
}
