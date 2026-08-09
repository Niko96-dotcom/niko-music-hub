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

    public func readNotes(in songFolder: URL) -> String? {
        let folder = songFolder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let url = folder.appendingPathComponent(Self.fileName)
        let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(resolvedURL, in: resolvedFolder) else { return nil }

        // `O_NOFOLLOW` closes the time-of-check/time-of-use gap for a final-component
        // symlink. `O_NONBLOCK` also ensures a hostile FIFO named notes.txt cannot stall a scan.
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

    private func isContained(_ child: URL, in folder: URL) -> Bool {
        let parentPath = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        return child.path.hasPrefix(parentPath)
    }
}
