import Darwin
import Foundation

/// Reads optional `notes.txt` sidecar text from a song folder root (read-only).
public struct SidecarNotesReader: @unchecked Sendable {
    public static let fileName = "notes.txt"
    /// A sidecar is a convenience annotation, not an unbounded document store.
    /// Keeping this finite prevents a malformed archive from being retained in every catalog snapshot.
    public static let maximumByteCount = 64 * 1024
    public static let truncationMarker = "\n… (notes.txt truncated at 64 KiB)"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Runs once per song on every scan, so it asks the filesystem once: the `open` below is the
    /// whole check. A missing folder, a folder that is a file, or a missing `notes.txt` fails the
    /// open. `O_NOFOLLOW` refuses `notes.txt` when it is a symbolic link, the only way a file
    /// named directly inside the folder can resolve outside it. So a separate existence check
    /// and a resolve-both-paths containment check would only repeat it, at a `stat` plus two
    /// path resolutions per song. The folder itself may be reached through a link, as before.
    public func readNotes(in songFolder: URL) -> String? {
        let url = songFolder.standardizedFileURL.appendingPathComponent(Self.fileName)

        // Checking at open time leaves no time-of-check/time-of-use gap for a final-component
        // symlink. `O_NONBLOCK` ensures a hostile FIFO named notes.txt cannot stall a scan.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }

        let data: Data
        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            data = try handle.read(upToCount: Self.maximumByteCount) ?? Data()
        } catch {
            return nil
        }

        var text = String(decoding: data, as: UTF8.self)
        if status.st_size > off_t(Self.maximumByteCount) {
            text += Self.truncationMarker
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
