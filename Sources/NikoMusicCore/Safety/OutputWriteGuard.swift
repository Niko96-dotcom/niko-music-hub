import Foundation

public enum OutputWriteGuardError: Error, Equatable, Sendable, LocalizedError {
    case outputInsideArchiveRoot(URL)

    public var errorDescription: String? {
        switch self {
        case .outputInsideArchiveRoot(let url):
            return "The output folder cannot be inside a Cubase archive root. Choose a folder outside your archive: \(url.path)"
        }
    }
}

public struct OutputWriteGuard: Sendable {
    private let policy: ReadOnlyArchivePolicy

    public init(fileManager: FileManager = .default) {
        self.policy = ReadOnlyArchivePolicy(fileManager: fileManager)
    }

    public func validateCanWriteOutput(to outputFolder: URL, archiveRoots: [URL]) throws {
        guard !archiveRoots.isEmpty else { return }
        do {
            try policy.enforceNoWrite(at: outputFolder, archiveRoots: archiveRoots)
        } catch ReadOnlyArchivePolicyError.writeDenied {
            throw OutputWriteGuardError.outputInsideArchiveRoot(outputFolder)
        }
    }
}
