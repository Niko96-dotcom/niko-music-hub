import Foundation

/// NMH-049 copy: nearby recovery sentences for open/scan failures.
/// The footer `statusMessage` remains the technical log; these strings are
/// shown next to the failing action.
public enum ArchiveOpenErrorCopy {
    /// Nearby recovery copy for a missing project file (verbatim).
    public static let missingProject = "This project file is missing. Reveal the song folder or rescan."
    /// Scan card title (verbatim).
    public static let scanTitle = "Scan failed"
    /// Scan card body (verbatim). `scanError` equals this string.
    public static let scanBody = "The archive scan did not finish. Try again, or check that the folder is still available."
    /// Scan retry button (verb, verbatim).
    public static let tryAgain = "Try Again"
    /// Reveal button shown next to the open error (verbatim).
    public static let revealSongFolder = "Reveal Song Folder"
}
