import AppCore
import Foundation
import NikoMusicCore

public struct StemSeparationService: Sendable {
    public static let toolID: ToolFeatureID = "stem-separation"

    private let backend: any StemSeparationBackend
    private let outputInboxStore: any OutputInboxStore
    private let jobRunner: any JobRunning
    private let archiveRootsProvider: @Sendable () throws -> [URL]
    private let outputWriteGuard: OutputWriteGuard

    public init(
        backend: any StemSeparationBackend,
        outputInboxStore: any OutputInboxStore,
        jobRunner: any JobRunning,
        archiveRootsProvider: @escaping @Sendable () throws -> [URL] = { [] },
        outputWriteGuard: OutputWriteGuard = OutputWriteGuard()
    ) {
        self.backend = backend
        self.outputInboxStore = outputInboxStore
        self.jobRunner = jobRunner
        self.archiveRootsProvider = archiveRootsProvider
        self.outputWriteGuard = outputWriteGuard
    }

    @discardableResult
    public func startJob(request: StemSeparationRequest) -> Job {
        let title = request.title ?? defaultTitle(for: request.inputURL)
        return jobRunner.enqueue(title: title, sourceToolID: Self.toolID) { progress in
            try await self.separate(request: request, progress: progress)
        }
    }

    public func separate(
        request: StemSeparationRequest,
        progress: JobProgress
    ) async throws {
        let title = request.title ?? defaultTitle(for: request.inputURL)
        let outputFolderURL = uniqueOutputFolder(
            root: request.outputRootURL,
            title: title,
            preset: request.preset
        )
        let backendRequest = StemSeparationBackendRequest(
            inputURL: request.inputURL,
            outputFolderURL: outputFolderURL,
            preset: request.preset
        )
        try Task.checkCancellation()
        try validateOutputDirectory(outputFolderURL)
        try await runJob(
            backendRequest: backendRequest,
            preset: request.preset,
            title: title,
            progress: progress
        )
    }

    private func runJob(
        backendRequest: StemSeparationBackendRequest,
        preset: StemSeparationPreset,
        title: String,
        progress: JobProgress
    ) async throws {
        progress.log("Creating output folder...")
        try Task.checkCancellation()
        try createDirectory(at: backendRequest.outputFolderURL)

        progress.log("Starting \(preset.displayName) separation...")
        let backend = self.backend
        let result = await withTaskCancellationHandler(operation: {
            await backend.separate(request: backendRequest) { fraction, message in
                progress.update(progress: fraction, message: message)
            }
        }, onCancel: {
            backend.cancel()
        })
        try Task.checkCancellation()

        switch result {
        case .canceled:
            progress.log("Canceled.")
            throw CancellationError()
        case .failed(let message):
            progress.log("Failed: \(message)")
            throw StemSeparationServiceError(message)
        case .success(let outputFolderURL, _):
            try await handleSuccess(
                outputFolderURL: outputFolderURL,
                preset: preset,
                title: title,
                progress: progress
            )
        }
    }

    private func handleSuccess(
        outputFolderURL: URL,
        preset: StemSeparationPreset,
        title: String,
        progress: JobProgress
    ) async throws {
        progress.log("Scanning outputs...")
        let scanner = StemOutputScanner()
        switch scanner.scan(outputFolderURL: outputFolderURL, expectedRoles: preset.expectedStemRoles) {
        case .failed(let message):
            progress.log("Output validation failed: \(message)")
            throw StemSeparationServiceError(message)
        case .success(let scannedStems):
            progress.log("Found \(scannedStems.count) stems.")
            let stems = renamedWithTitle(scannedStems, title: title)
            progress.setOutputFileURLs(stems.map(\.fileURL))
            try addInboxItems(stems: stems)
        }
    }

    /// Backends emit bare role names ("vocals.wav"); carry the source title into the
    /// filename ("Song Name - Vocals.wav") so dragged stems identify their song in a DAW.
    /// Best effort per stem — a failed rename keeps the scanned file usable.
    private func renamedWithTitle(_ stems: [StemOutput], title: String) -> [StemOutput] {
        let sanitized = sanitizedTitle(title)
        guard !sanitized.isEmpty else { return stems }
        return stems.map { stem in
            let target = stem.fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(sanitized) - \(stem.role.displayName)")
                .appendingPathExtension(stem.fileURL.pathExtension)
            guard target.path != stem.fileURL.path else { return stem }
            do {
                try FileManager.default.moveItem(at: stem.fileURL, to: target)
                return StemOutput(role: stem.role, fileURL: target)
            } catch {
                return stem
            }
        }
    }

    private func addInboxItems(stems: [StemOutput]) throws {
        for stem in stems {
            let item = OutputInboxItem(
                fileURL: stem.fileURL,
                sourceToolID: Self.toolID,
                status: .available,
                metadata: [
                    "role": stem.role.rawValue,
                    "displayName": stem.role.displayName
                ]
            )
            try outputInboxStore.addItem(item)
        }
    }

    private func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Enforces the archive write boundary before a workflow creates output folders.
    /// The provider is read at job time so cached tool sessions still honor current settings.
    func validateOutputDirectory(_ outputDirectoryURL: URL) throws {
        try outputWriteGuard.validateCanWriteOutput(
            to: outputDirectoryURL,
            archiveRoots: try archiveRootsProvider()
        )
    }

    private func sanitizedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    private func uniqueOutputFolder(
        root: URL,
        title: String,
        preset: StemSeparationPreset
    ) -> URL {
        let sanitized = sanitizedTitle(title)
        let timestamp = Date().timeIntervalSince1970
        let folderName = "\(sanitized) - \(preset.displayName) - \(timestamp)"
        return root
            .appendingPathComponent("Stems", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func defaultTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

public struct StemSeparationServiceError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
