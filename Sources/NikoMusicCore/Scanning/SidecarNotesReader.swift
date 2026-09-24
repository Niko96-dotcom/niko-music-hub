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

    /// Opens the song folder itself before reading anything below it, so a folder that
    /// is a symbolic link, a file, or missing yields no notes instead of text from elsewhere.
    /// The folder descriptor pins the directory: `notes.txt` is opened relative to it with
    /// `openat`, so swapping the folder for a link between enumeration and this read cannot
    /// redirect it. `O_NOFOLLOW` refuses `notes.txt` when it is itself a symbolic link, and
    /// `O_NONBLOCK` keeps a hostile FIFO of that name from stalling a scan. Both descriptors
    /// are closed on every path below.
    public func readNotes(in songFolder: URL) -> String? {
        let folderDescriptor = Darwin.open(
            songFolder.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard folderDescriptor >= 0 else { return nil }
        defer { Darwin.close(folderDescriptor) }

        return readNotesBorrowing(folderDescriptor)
    }

    /// Reads through the scan's pinned verified song-base fd without looking up its path.
    /// The borrowed fd remains owned by the caller.
    func readNotes(in songFolder: URL, borrowing baseDescriptor: Int32?) -> String? {
        guard let baseDescriptor else { return readNotes(in: songFolder) }
        return readNotesBorrowing(baseDescriptor)
    }

    private func readNotesBorrowing(_ folderDescriptor: Int32) -> String? {
        // Opened relative to the pinned folder, there is no time-of-check/time-of-use gap
        // for a final-component symlink. `O_NONBLOCK` ensures a hostile FIFO named
        // notes.txt cannot stall a scan.
        let descriptor = Darwin.openat(
            folderDescriptor,
            Self.fileName,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
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
