@preconcurrency import AVFAudio
import Foundation

public enum StemOutputScannerResult: Equatable, Sendable {
    case success([StemOutput])
    case failed(message: String)
}

public struct StemOutputScanner: Sendable {
    /// Formats a stem can arrive in. A role-named file with another extension is not a stem.
    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "flac", "mp3", "m4a", "caf"]

    public init() {}

    public func scan(
        outputFolderURL: URL,
        expectedRoles: [StemRole]
    ) -> StemOutputScannerResult {
        guard fileExists(at: outputFolderURL, isDirectory: true) else {
            return .failed(message: "Output folder does not exist.")
        }

        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: outputFolderURL.path)
        } catch {
            return .failed(message: "Could not read output folder: \(error.localizedDescription)")
        }

        var stems: [StemOutput] = []
        var seenRoles: Set<StemRole> = []

        for item in contents {
            let itemURL = outputFolderURL.appendingPathComponent(item)
            guard isInsideFolder(itemURL: itemURL, folderURL: outputFolderURL) else {
                return .failed(message: "Output file escapes the job folder: \(item)")
            }
            guard fileExists(at: itemURL, isDirectory: false) else { continue }

            guard let role = StemRole.role(for: item),
                  Self.audioExtensions.contains(itemURL.pathExtension.lowercased())
            else { continue }
            guard !seenRoles.contains(role) else {
                return .failed(message: "Duplicate output for \(role.displayName): \(item)")
            }
            // A file name and a zero exit code do not make a stem: it must be a regular
            // file that decodes to at least one audio frame.
            guard isReadableAudio(itemURL) else {
                return .failed(message: "\(role.displayName) stem is not readable audio: \(item)")
            }
            seenRoles.insert(role)
            stems.append(StemOutput(role: role, fileURL: itemURL))
        }

        stems.sort { $0.role.rawValue < $1.role.rawValue }

        let missingRoles = expectedRoles.filter { !seenRoles.contains($0) }
        guard missingRoles.isEmpty else {
            let names = missingRoles.map(\.displayName).joined(separator: ", ")
            return .failed(message: "Missing stems: \(names)")
        }

        return .success(stems)
    }

    private func fileExists(at url: URL, isDirectory: Bool) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue == isDirectory
    }

    private func isReadableAudio(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let file = try? AVAudioFile(forReading: resolved)
        else { return false }
        return file.length > 0
    }

    private func isInsideFolder(itemURL: URL, folderURL: URL) -> Bool {
        let itemPath = itemURL.resolvingSymlinksInPath().standardizedFileURL.path
        let folderPath = folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        // Boundary-aware: "/out/stems-other/x" is not inside "/out/stems".
        let folderPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return itemPath.hasPrefix(folderPrefix)
    }
}
