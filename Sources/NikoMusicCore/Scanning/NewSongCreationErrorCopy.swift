import Foundation

/// File-name-specific recovery copy for every `NewSongFolderCreator.CreationError` case (NMH-039).
/// Sentence case, no exclamation marks. Backs the `LocalizedError` conformance below.
public enum NewSongCreationErrorCopy: Sendable {
    public static func errorDescription(
        for error: NewSongFolderCreator.CreationError,
        name: String
    ) -> String {
        switch error {
        case .emptyName:
            return "Enter a song folder name."
        case .invalidName:
            return "Use a plain folder name without slashes or parent-folder segments."
        case .folderExists:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "A folder with that name already exists in New Song Drafts. Choose another name."
            }
            return "A folder named “\(name)” already exists in New Song Drafts. Choose another name."
        case .archiveRootIsReadOnly:
            return "The draft was not created because the output folder is inside an archive root. Choose another folder in Settings > Output, then try again."
        case .destinationUnavailable:
            return "The New Song Drafts folder could not be created. Check the output folder in Settings, then try again."
        case .templateMissing:
            return "The template folder is missing. Choose another folder or clear the template."
        case .templateUnreadable:
            return "The template folder could not be read. Choose another folder or clear the template."
        case .templateOverlap:
            return "That template folder overlaps the destination. Choose a different template folder."
        case .templateConflict(let filename):
            return "The template could not be copied because “\(filename)” already exists in the destination. Choose another name or template."
        case .templateCopyFailed:
            return "The template could not be copied. Choose another template or create the draft without one."
        case .stagingFailed:
            return "The draft could not be prepared. Check the output folder, then try again."
        case .stagingValidationFailed:
            return "The draft failed a safety check and was not created. Try another name."
        case .finalizationFailed:
            return "The draft could not be finished. Check the output folder, then try again."
        }
    }
}

extension NewSongFolderCreator.CreationError: LocalizedError {
    public var errorDescription: String? {
        // No name travels with the error value itself; callers that know the
        // typed folder name must use `NewSongCreationErrorCopy.errorDescription(for:name:)`
        // directly so the message can include it (NMH-039 Accept 3).
        NewSongCreationErrorCopy.errorDescription(for: self, name: "")
    }
}
