import AppCore
import Foundation

public typealias AudioConversionPipelineFactory = @Sendable (AppSettings) -> any AudioConverting
public typealias BatchAudioConversionProgressHandler = @Sendable (BatchAudioConversionUpdate) -> Void

public struct BatchAudioConversionUseCase: @unchecked Sendable {
    private let settingsStore: any SettingsStore
    private let outputInboxStore: any OutputInboxStore
    private let converterFactory: AudioConversionPipelineFactory

    public init(
        settingsStore: any SettingsStore,
        outputInboxStore: any OutputInboxStore,
        converterFactory: @escaping AudioConversionPipelineFactory = { settings in
            AudioConversionPipeline(helperSettings: settings.helperTools)
        }
    ) {
        self.settingsStore = settingsStore
        self.outputInboxStore = outputInboxStore
        self.converterFactory = converterFactory
    }

    public func convert(
        files: [BatchAudioConversionFile],
        stopController: StopAfterCurrentController,
        progress: BatchAudioConversionProgressHandler? = nil
    ) async throws -> [BatchAudioConversionOutcome] {
        guard !files.isEmpty else { return [] }

        let settings = try settingsStore.loadSettings()
        let converter = converterFactory(settings)
        var outcomes: [BatchAudioConversionOutcome] = []

        for (index, file) in files.enumerated() {
            if stopController.isStopRequested {
                let outcome = skippedOutcome(for: file, index: index, total: files.count)
                outcomes.append(outcome)
                progress?(outcome.update)
                continue
            }

            progress?(BatchAudioConversionUpdate(
                fileID: file.id,
                status: .converting,
                fileProgress: 0,
                overallProgress: overallProgress(completed: index, total: files.count)
            ))

            let request = ConversionRequest(
                sourceURL: file.sourceURL,
                outputDirectory: settings.outputFolder.url,
                preset: settings.audioPreset,
                sourceType: file.sourceType
            )

            let outcome: BatchAudioConversionOutcome
            do {
                let result = try await converter.convert(request)
                try addOutputInboxItem(for: file, result: result)
                outcome = BatchAudioConversionOutcome(
                    file: file,
                    status: .verified(result),
                    fileProgress: 1,
                    overallProgress: overallProgress(completed: index + 1, total: files.count)
                )
            } catch {
                outcome = BatchAudioConversionOutcome(
                    file: file,
                    status: .failed(message: failureMessage(for: error)),
                    fileProgress: 1,
                    overallProgress: overallProgress(completed: index + 1, total: files.count)
                )
            }

            outcomes.append(outcome)
            progress?(outcome.update)
        }

        return outcomes
    }

    private func addOutputInboxItem(
        for file: BatchAudioConversionFile,
        result: ConversionResult
    ) throws {
        let item = OutputInboxItem(
            fileURL: result.outputURL,
            sourceToolID: "wav-converter",
            status: .available,
            metadata: [
                "sourceFile": file.sourceURL.path,
                "sampleRate": "\(result.spec.sampleRate)",
                "bitDepth": "\(result.spec.bitDepth)",
                "channels": "\(result.spec.channelCount)",
                "converter": result.converterPath.displayName,
                "sourceType": file.sourceType.rawValue
            ]
        )
        try outputInboxStore.addItem(item)
    }

    private func skippedOutcome(
        for file: BatchAudioConversionFile,
        index: Int,
        total: Int
    ) -> BatchAudioConversionOutcome {
        BatchAudioConversionOutcome(
            file: file,
            status: .skipped,
            fileProgress: 0,
            overallProgress: overallProgress(completed: index + 1, total: total)
        )
    }

    private func overallProgress(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return Double(completed) / Double(total)
    }

    private func failureMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

public final class StopAfterCurrentController: @unchecked Sendable {
    private let lock = NSLock()
    private var stopRequested = false

    public init() {}

    public var isStopRequested: Bool {
        lock.withLock { stopRequested }
    }

    public func requestStopAfterCurrent() {
        lock.withLock {
            stopRequested = true
        }
    }
}

public struct BatchAudioConversionFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceURL: URL
    public var sourceType: SupportedAudioFileType

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceType: SupportedAudioFileType
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceType = sourceType
    }
}

public enum BatchAudioConversionStatus: Equatable, Sendable {
    case converting
    case verified(ConversionResult)
    case failed(message: String)
    case skipped
}

public struct BatchAudioConversionUpdate: Equatable, Sendable {
    public var fileID: UUID
    public var status: BatchAudioConversionStatus
    public var fileProgress: Double
    public var overallProgress: Double

    public init(
        fileID: UUID,
        status: BatchAudioConversionStatus,
        fileProgress: Double,
        overallProgress: Double
    ) {
        self.fileID = fileID
        self.status = status
        self.fileProgress = fileProgress
        self.overallProgress = overallProgress
    }
}

public struct BatchAudioConversionOutcome: Equatable, Sendable {
    public var file: BatchAudioConversionFile
    public var status: BatchAudioConversionStatus
    public var fileProgress: Double
    public var overallProgress: Double

    public init(
        file: BatchAudioConversionFile,
        status: BatchAudioConversionStatus,
        fileProgress: Double,
        overallProgress: Double
    ) {
        self.file = file
        self.status = status
        self.fileProgress = fileProgress
        self.overallProgress = overallProgress
    }

    public var update: BatchAudioConversionUpdate {
        BatchAudioConversionUpdate(
            fileID: file.id,
            status: status,
            fileProgress: fileProgress,
            overallProgress: overallProgress
        )
    }
}

public extension AudioConverterPath {
    var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .ffmpeg:
            return "FFmpeg"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
