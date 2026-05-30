import Foundation

public protocol FileActions: Sendable {
    @MainActor
    func chooseOutputFolder() -> URL?

    /// Opens a directory picker with the given prompt (e.g. archive root, output folder).
    @MainActor
    func chooseDirectory(prompt: String) -> URL?

    /// Opens a file picker for an executable (ffmpeg, yt-dlp, etc.).
    @MainActor
    func chooseExecutable(prompt: String) -> URL?

    @MainActor
    func revealInFinder(_ url: URL)
}
