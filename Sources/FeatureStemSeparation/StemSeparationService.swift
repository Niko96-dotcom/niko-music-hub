import AppCore
import Foundation
import NikoMusicCore

public struct StemSeparationService: Sendable {
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
        return jobRunner.enqueue(title: title, sourceToolID: .stemSeparation) { progress in
            try await self.separate(request: request, progress: progress)
        }
    }

    public func separate(
        request: StemSeparationRequest,
        progress: JobProgress
    ) async throws {
        let title = request.title ?? defaultTitle(for: request.inputURL)
        let outputFolderURL = uniqueOutputFolder(
            root: request.destination.folder,
            title: title,
            preset: request.preset
        )
        let backendRequest = StemSeparationBackendRequest(
            inputURL: request.inputURL,
            outputFolderURL: outputFolderURL,
            preset: request.preset
        )
        try Task.checkCancellation()
        // Enforces the archive write boundary before the run creates its folder.
        try request.destination.validate(outputFolderURL)
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
        case let .failed(message, reason):
            progress.log("Failed: \(message)")
            throw StemSeparationServiceError(message, reason: reason)
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
            progress.log("Found \(CountCopy.count(scannedStems.count, "stem")).")
            let stems = renamedWithTitle(scannedStems, title: title)
            do {
                try addInboxItems(stems: stems)
            } catch {
                // Stem files stay where they are; only the inbox handoff failed.
                progress.log("Inbox handoff failed: \(error.localizedDescription)")
                throw StemSeparationServiceError(
                    "Stems were saved to \(outputFolderURL.path), but couldn't be added to the Output Inbox."
                )
            }
            progress.setOutputFileURLs(stems.map(\.fileURL))
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
        // One store write: a failure leaves no rows, never half a set.
        let items = stems.map { stem in
            OutputInboxItem(
                fileURL: stem.fileURL,
                sourceToolID: .stemSeparation,
                status: .available,
                metadata: [
                    "role": stem.role.rawValue,
                    "displayName": stem.role.displayName
                ]
            )
        }
        try outputInboxStore.addItems(items)
    }

    private func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// UTF-8 bytes kept from the title. APFS allows 255 bytes per name, and the job
    /// folder adds about 85 bytes (" - preset - timestamp - uuid").
    static let maxTitleBytes = 150

    private func sanitizedTitle(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.utf8.count > Self.maxTitleBytes else { return cleaned }
        // Cut at a character boundary so no multibyte character is split.
        var truncated = ""
        var byteCount = 0
        for character in cleaned {
            let characterBytes = character.utf8.count
            guard byteCount + characterBytes <= Self.maxTitleBytes else { break }
            truncated.append(character)
            byteCount += characterBytes
        }
        return truncated.trimmingCharacters(in: .whitespaces)
    }

    private func uniqueOutputFolder(
        root: URL,
        title: String,
        preset: StemSeparationPreset
    ) -> URL {
        let sanitized = sanitizedTitle(title)
        let timestamp = Date().timeIntervalSince1970
        let uniqueSuffix = UUID().uuidString.lowercased()
        let folderName = "\(sanitized) - \(preset.displayName) - \(timestamp) - \(uniqueSuffix)"
        return root
            .appendingPathComponent("Stems", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func defaultTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

public struct StemSeparationServiceError: LocalizedError, Equatable, Sendable, JobFailureReasonProviding {
    public let message: String
    public let reason: JobFailureReason?

    public init(message: String, reason: JobFailureReason? = nil) {
        self.message = message
        self.reason = reason
    }

    public init(_ message: String, reason: JobFailureReason? = nil) {
        self.message = message
        self.reason = reason
    }

    public var errorDescription: String? { message }

    public var jobFailureReason: JobFailureReason? { reason }
}
