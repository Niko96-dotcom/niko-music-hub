import AppCore
import Foundation

public struct StemSeparationService: Sendable {
    public static let toolID: ToolFeatureID = "stem-separation"

    private let backend: any StemSeparationBackend
    private let outputInboxStore: any OutputInboxStore
    private let jobRunner: any JobRunning

    public init(
        backend: any StemSeparationBackend,
        outputInboxStore: any OutputInboxStore,
        jobRunner: any JobRunning
    ) {
        self.backend = backend
        self.outputInboxStore = outputInboxStore
        self.jobRunner = jobRunner
    }

    @discardableResult
    public func startJob(request: StemSeparationRequest) -> Job {
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

        return jobRunner.enqueue(title: title, sourceToolID: Self.toolID) { progress in
            try await self.runJob(
                backendRequest: backendRequest,
                preset: request.preset,
                progress: progress
            )
        }
    }

    private func runJob(
        backendRequest: StemSeparationBackendRequest,
        preset: StemSeparationPreset,
        progress: JobProgress
    ) async throws {
        progress.log("Creating output folder...")
        try createDirectory(at: backendRequest.outputFolderURL)

        progress.log("Starting \(preset.displayName) separation...")
        let result = await backend.separate(request: backendRequest) { fraction, message in
            progress.update(progress: fraction, message: message)
        }

        switch result {
        case .canceled:
            progress.log("Canceled.")
            throw CancellationError()
        case .failed(let message):
            progress.log("Failed: \(message)")
            throw StemSeparationServiceError(message)
        case .success(_, _):
            try await handleSuccess(
                outputFolderURL: backendRequest.outputFolderURL,
                preset: preset,
                progress: progress
            )
        }
    }

    private func handleSuccess(
        outputFolderURL: URL,
        preset: StemSeparationPreset,
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
            progress.setOutputFileURLs(scannedStems.map(\.fileURL))
            try addInboxItems(stems: scannedStems)
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

    private func uniqueOutputFolder(
        root: URL,
        title: String,
        preset: StemSeparationPreset
    ) -> URL {
        let sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespaces)
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
