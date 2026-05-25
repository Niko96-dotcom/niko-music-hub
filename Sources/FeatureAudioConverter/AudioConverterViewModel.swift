import AppCore
import Combine
import Foundation

@MainActor
public final class AudioConverterViewModel: ObservableObject, @unchecked Sendable {
    @Published public private(set) var rows: [AudioConverterRow] = []
    @Published public private(set) var notices: [String] = []
    @Published public private(set) var isConverting = false
    @Published public private(set) var overallProgress = 0.0
    @Published public private(set) var statusText = AudioConverterCopy.ready
    @Published public private(set) var currentAudioPreset: AudioPreset

    private let context: ToolContext
    private let scanner: AudioFileIntakeScanner
    private let batchUseCase: BatchAudioConversionUseCase
    private let outputFileNamer: OutputFileNamer
    private let ffmpegHealthChecker: FFmpegHealthChecker
    private var stopController: StopAfterCurrentController?
    private var conversionTask: Task<Void, Never>?

    public static let supportedSampleRates = [44100, 48000, 88200, 96000]
    public static let supportedBitDepths = [16, 24, 32]

    public init(
        context: ToolContext,
        scanner: AudioFileIntakeScanner = AudioFileIntakeScanner(),
        batchUseCase: BatchAudioConversionUseCase? = nil,
        outputFileNamer: OutputFileNamer = OutputFileNamer(),
        ffmpegHealthChecker: FFmpegHealthChecker = FFmpegHealthChecker()
    ) {
        self.context = context
        self.scanner = scanner
        self.batchUseCase = batchUseCase ?? BatchAudioConversionUseCase(
            settingsStore: context.settingsStore,
            outputInboxStore: context.outputInboxStore
        )
        self.outputFileNamer = outputFileNamer
        self.ffmpegHealthChecker = ffmpegHealthChecker
        self.currentAudioPreset = (try? context.settingsStore.loadSettings().audioPreset) ?? .cubaseDefault
    }

    deinit {
        conversionTask?.cancel()
    }

    public var canConvertToWAV: Bool {
        !isConverting && rows.contains { $0.state == .queued && $0.isConvertible }
    }

    public var canRequestStopAfterCurrent: Bool {
        isConverting && stopController?.isStopRequested == false
    }

    public var queuedConvertibleCount: Int {
        rows.filter { $0.state == .queued && $0.isConvertible }.count
    }

    public var presetSummaryText: String {
        "\(Self.sampleRateLabel(for: currentAudioPreset.sampleRate)) - \(currentAudioPreset.bitDepth)-bit - \(Self.channelModeLabel(for: currentAudioPreset.channelMode))"
    }

    public func addFileURLs(_ urls: [URL]) {
        do {
            let intake = try scanner.scan(urls)
            rows.append(contentsOf: intake.supportedFiles.map(makeQueuedRow))
            rows.append(contentsOf: intake.unsupportedFiles.map(makeUnsupportedRow))
            notices = intake.notices.map(noticeText)
            refreshStatusText()
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func startConversion() {
        guard canConvertToWAV else { return }
        conversionTask = Task { @MainActor in
            _ = await convertQueuedRows()
        }
    }

    @discardableResult
    public func convertQueuedRows() async -> [BatchAudioConversionOutcome] {
        let files = rows.compactMap { row -> BatchAudioConversionFile? in
            guard row.state == .queued,
                  let sourceType = row.sourceType else {
                return nil
            }
            return BatchAudioConversionFile(
                id: row.id,
                sourceURL: row.sourceURL,
                sourceType: sourceType
            )
        }
        guard !files.isEmpty else { return [] }

        let controller = StopAfterCurrentController()
        stopController = controller
        isConverting = true
        statusText = AudioConverterCopy.converting
        overallProgress = 0

        do {
            let outcomes = try await batchUseCase.convert(
                files: files,
                stopController: controller,
                progress: { [weak self] update in
                    Task { @MainActor in
                        self?.apply(update)
                    }
                }
            )
            outcomes.forEach { apply($0.update) }
            overallProgress = outcomes.last?.overallProgress ?? overallProgress
            isConverting = false
            stopController = nil
            refreshStatusText()
            return outcomes
        } catch {
            rows = rows.map { row in
                guard row.state == .queued || row.state == .converting else {
                    return row
                }
                return row.updated(
                    state: .failed,
                    statusText: error.localizedDescription,
                    progress: 1
                )
            }
            isConverting = false
            stopController = nil
            statusText = error.localizedDescription
            return []
        }
    }

    public func requestStopAfterCurrent() {
        stopController?.requestStopAfterCurrent()
    }

    public func updateWAVPreset(sampleRate: Int, bitDepth: Int, channelMode: AudioChannelMode) {
        guard Self.supportedSampleRates.contains(sampleRate),
              Self.supportedBitDepths.contains(bitDepth) else {
            return
        }

        let updatedPreset = AudioPreset(
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: Self.channelCount(for: channelMode),
            channelMode: channelMode
        )

        do {
            try context.settingsStore.updateSettings { settings in
                settings.audioPreset = updatedPreset
            }
            currentAudioPreset = updatedPreset
            refreshQueuedOutputNames()
            statusText = AudioConverterCopy.ready
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func retryAfterChoosingFFmpeg(rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }),
              rows[index].recoveryActionTitle == AudioConverterCopy.chooseFFmpeg else {
            return
        }

        rows[index] = rows[index].updated(
            state: .queued,
            statusText: AudioConverterCopy.ready,
            progress: 0,
            outputURL: nil,
            converterPathLabel: nil,
            recoveryActionTitle: nil
        )
        refreshStatusText()
    }

    public func chooseFFmpegAndRetry(rowID: UUID, ffmpegURL: URL) async {
        guard rows.contains(where: {
            $0.id == rowID && $0.recoveryActionTitle == AudioConverterCopy.chooseFFmpeg
        }) else {
            return
        }

        do {
            var settings = try context.settingsStore.loadSettings()
            settings.helperTools.ffmpeg = ffmpegURL

            switch await ffmpegHealthChecker.availability(settings: settings.helperTools) {
            case .available:
                try context.settingsStore.saveSettings(settings)
                retryAfterChoosingFFmpeg(rowID: rowID)
            case .missing:
                markFFmpegSelectionFailed(
                    rowID: rowID,
                    message: AudioConverterCopy.selectedFFmpegMissing
                )
            case let .unusable(message):
                markFFmpegSelectionFailed(
                    rowID: rowID,
                    message: AudioConverterCopy.selectedFFmpegUnusable(message)
                )
            }
        } catch {
            markFFmpegSelectionFailed(
                rowID: rowID,
                message: error.localizedDescription
            )
        }
    }

    private func makeQueuedRow(_ file: ScannedAudioFile) -> AudioConverterRow {
        AudioConverterRow(
            sourceURL: file.url,
            sourceType: file.sourceType,
            plannedOutputName: plannedOutputName(for: file.url),
            state: .queued,
            statusText: AudioConverterCopy.ready,
            progress: 0
        )
    }

    private func makeUnsupportedRow(_ file: UnsupportedAudioFile) -> AudioConverterRow {
        AudioConverterRow(
            sourceURL: file.url,
            sourceType: nil,
            plannedOutputName: "-",
            state: .unsupported,
            statusText: AudioConverterCopy.unsupported,
            progress: 0
        )
    }

    private func plannedOutputName(for sourceURL: URL) -> String {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        return outputFileNamer.plannedOutputURL(
            for: settings.outputFolder.url,
            sourceURL: sourceURL,
            preset: settings.audioPreset,
            existingFileExists: { _ in false }
        )
        .lastPathComponent
    }

    private func refreshQueuedOutputNames() {
        rows = rows.map { row in
            guard row.state == .queued, row.isConvertible else {
                return row
            }

            var updatedRow = row
            updatedRow.plannedOutputName = plannedOutputName(for: row.sourceURL)
            return updatedRow
        }
    }

    private func noticeText(_ notice: AudioFileIntakeNotice) -> String {
        switch notice {
        case let .subfoldersIgnored(_, count):
            return count == 1 ? "1 subfolder ignored" : "\(count) subfolders ignored"
        }
    }

    private func apply(_ update: BatchAudioConversionUpdate) {
        guard let index = rows.firstIndex(where: { $0.id == update.fileID }) else { return }
        guard let updatedRow = row(rows[index], applying: update) else { return }
        rows[index] = updatedRow
        overallProgress = update.overallProgress
    }

    private func row(
        _ row: AudioConverterRow,
        applying update: BatchAudioConversionUpdate
    ) -> AudioConverterRow? {
        switch update.status {
        case .converting:
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .converting,
                statusText: AudioConverterCopy.converting,
                progress: update.fileProgress
            )
        case let .verified(result):
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .verified,
                statusText: AudioConverterCopy.verified,
                progress: update.fileProgress,
                outputURL: result.outputURL,
                converterPathLabel: result.converterPath.displayName,
                recoveryActionTitle: nil
            )
        case let .failed(message):
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .failed,
                statusText: visibleFailureCopy(for: message),
                progress: update.fileProgress,
                recoveryActionTitle: recoveryActionTitle(for: message)
            )
        case .skipped:
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .skipped,
                statusText: AudioConverterCopy.skipped,
                progress: update.fileProgress
            )
        }
    }

    private func markFFmpegSelectionFailed(rowID: UUID, message: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index] = rows[index].updated(
            state: .failed,
            statusText: message,
            progress: 1,
            recoveryActionTitle: AudioConverterCopy.chooseFFmpeg
        )
        statusText = message
    }

    private func visibleFailureCopy(for message: String) -> String {
        if message == AudioConverterCopy.missingFFmpeg {
            return AudioConverterCopy.missingFFmpeg
        }
        if message.localizedCaseInsensitiveContains("verification") {
            return AudioConverterCopy.verificationFailed
        }
        return AudioConverterCopy.genericFailure
    }

    private func recoveryActionTitle(for message: String) -> String? {
        message == AudioConverterCopy.missingFFmpeg ? AudioConverterCopy.chooseFFmpeg : nil
    }

    private func refreshStatusText() {
        if rows.contains(where: { $0.state == .verified }) {
            statusText = AudioConverterCopy.verified
        } else {
            statusText = AudioConverterCopy.ready
        }
    }

    private static func channelCount(for channelMode: AudioChannelMode) -> Int {
        switch channelMode {
        case .mono:
            return 1
        case .preserveMonoStereo, .stereo:
            return 2
        }
    }

    private static func sampleRateLabel(for sampleRate: Int) -> String {
        switch sampleRate {
        case 44100:
            return "44.1 kHz"
        case 48000:
            return "48 kHz"
        case 88200:
            return "88.2 kHz"
        case 96000:
            return "96 kHz"
        default:
            return "\(sampleRate) Hz"
        }
    }

    private static func channelModeLabel(for channelMode: AudioChannelMode) -> String {
        switch channelMode {
        case .preserveMonoStereo:
            return "Preserve mono/stereo"
        case .mono:
            return "Mono"
        case .stereo:
            return "Stereo"
        }
    }
}

public enum AudioConverterRowState: String, Codable, Sendable, CaseIterable {
    case queued
    case converting
    case verified
    case failed
    case unsupported
    case skipped
}

public struct AudioConverterRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceURL: URL
    public var sourceType: SupportedAudioFileType?
    public var plannedOutputName: String
    public var state: AudioConverterRowState
    public var statusText: String
    public var progress: Double
    public var outputURL: URL?
    public var converterPathLabel: String?
    public var recoveryActionTitle: String?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceType: SupportedAudioFileType?,
        plannedOutputName: String,
        state: AudioConverterRowState,
        statusText: String,
        progress: Double,
        outputURL: URL? = nil,
        converterPathLabel: String? = nil,
        recoveryActionTitle: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.plannedOutputName = plannedOutputName
        self.state = state
        self.statusText = statusText
        self.progress = progress
        self.outputURL = outputURL
        self.converterPathLabel = converterPathLabel
        self.recoveryActionTitle = recoveryActionTitle
    }

    public var isConvertible: Bool {
        sourceType != nil && state != .unsupported
    }

    public func isDragReady(fileManager: FileManager = .default) -> Bool {
        verifiedOutputURLForDrag(fileManager: fileManager) != nil
    }

    public func verifiedOutputURLForDrag(fileManager: FileManager = .default) -> URL? {
        guard state == .verified,
              let outputURL else {
            return nil
        }

        let item = OutputInboxItem(
            fileURL: outputURL,
            sourceToolID: "wav-converter",
            status: .available
        )
        return OutputHandoff.dragFileURL(for: item, fileManager: fileManager)
    }

    public func updated(
        state: AudioConverterRowState,
        statusText: String,
        progress: Double,
        outputURL: URL? = nil,
        converterPathLabel: String? = nil,
        recoveryActionTitle: String? = nil
    ) -> AudioConverterRow {
        AudioConverterRow(
            id: id,
            sourceURL: sourceURL,
            sourceType: sourceType,
            plannedOutputName: outputURL?.lastPathComponent ?? plannedOutputName,
            state: state,
            statusText: statusText,
            progress: progress,
            outputURL: outputURL ?? self.outputURL,
            converterPathLabel: converterPathLabel ?? self.converterPathLabel,
            recoveryActionTitle: recoveryActionTitle
        )
    }
}

public enum AudioConverterCopy {
    public static let ready = "Ready for WAV conversion"
    public static let converting = "Converting to Cubase-ready WAV"
    public static let verified = "Verified WAV ready"
    public static let unsupported = "This file type is not supported in Phase 3. Add M4A, MP3, WAV, AIFF, or FLAC instead."
    public static let missingFFmpeg = "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
    public static let verificationFailed = "WAV verification failed. The source file was left untouched; check the output preset and try again."
    public static let genericFailure = "Could not convert this file. Keep the source selected, review the row message, then try Convert to WAV again."
    public static let skipped = "Skipped"
    public static let chooseFFmpeg = "Choose FFmpeg"
    public static let selectedFFmpegMissing = "Selected FFmpeg could not be found. Choose FFmpeg, then pick the executable again."

    public static func selectedFFmpegUnusable(_ message: String) -> String {
        "Selected FFmpeg could not be used: \(message)"
    }
}
