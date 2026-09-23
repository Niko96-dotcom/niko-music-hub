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
    private var conversionTask: Task<[BatchAudioConversionOutcome], Never>?
    private var isCancelRequested = false
    private var handoffSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var deferredDurableSettings: AppSettings?
    private var activeBatchSettings: AppSettings?

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
        self.currentAudioPreset = context.appSettings.settings.audioPreset
        settingsSubscription = context.appSettings.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                self.applyDurableSettingsChange(settings)
            }
    }

    deinit {
        conversionTask?.cancel()
    }

    public var canConvertToWAV: Bool {
        !isConverting && rows.contains { $0.state == .queued && $0.isConvertible }
    }

    public var canRequestStopAfterCurrent: Bool {
        isConverting && !isCancelRequested && stopController?.isStopRequested == false
    }

    public var queuedConvertibleCount: Int {
        rows.filter { $0.state == .queued && $0.isConvertible }.count
    }

    public var presetSummaryText: String {
        "\(Self.sampleRateLabel(for: currentAudioPreset.sampleRate)) - \(currentAudioPreset.bitDepth)-bit - \(Self.channelModeLabel(for: currentAudioPreset.channelMode))"
    }

    /// Drain files other tools hand off through the router (Archive → "Convert preview").
    /// The shell keeps visited tool panes mounted, so the view's `onAppear` never fires
    /// for a handoff that arrives while the converter is already alive; the session
    /// view model owns the subscription instead. `@Published` emits on `willSet`, so the
    /// router is read on the next main-queue turn, after its stored value is updated.
    public func bindConverterHandoff(to router: QuickAccessRouter) {
        handoffSubscription = router.$prefilledConverterURLs
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak router] _ in
                guard let self, let router else { return }
                let urls = router.consumePrefilledConverterURLs()
                guard !urls.isEmpty else { return }
                self.addFileURLs(urls)
            }
    }

    public func addFileURLs(_ urls: [URL]) {
        do {
            let intake = try scanner.scan(urls)
            var knownURLs = Set(rows.map { $0.sourceURL.standardizedFileURL })
            let newSupported = intake.supportedFiles.filter { file in
                let key = file.url.standardizedFileURL
                guard !knownURLs.contains(key) else { return false }
                knownURLs.insert(key)
                return true
            }
            let newUnsupported = intake.unsupportedFiles.filter { file in
                let key = file.url.standardizedFileURL
                guard !knownURLs.contains(key) else { return false }
                knownURLs.insert(key)
                return true
            }
            rows.append(contentsOf: newSupported.map(makeQueuedRow))
            rows.append(contentsOf: newUnsupported.map(makeUnsupportedRow))
            notices.append(contentsOf: intake.notices.map(noticeText))
            if notices.count > 10 {
                notices = Array(notices.suffix(10))
            }
            refreshStatusText()
        } catch {
            statusText = error.localizedDescription
        }
    }

    public func removeRow(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        if isConverting && rows[index].state == .converting { return }
        rows.remove(at: index)
        refreshStatusText()
    }

    public func clearAll() {
        guard !isConverting else { return }
        guard !rows.isEmpty else { return }
        rows.removeAll()
        refreshStatusText()
    }

    public func startConversion() {
        _ = launchConversion()
    }

    @discardableResult
    public func convertQueuedRows() async -> [BatchAudioConversionOutcome] {
        guard let task = launchConversion() else { return [] }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Every run lives in `conversionTask` so `cancelConversion()` can cancel it: the
    /// process runner then terminates FFmpeg's process group and the native path stops
    /// at its next buffer.
    private func launchConversion() -> Task<[BatchAudioConversionOutcome], Never>? {
        guard !isConverting else { return nil }
        let files = queuedConversionFiles()
        guard !files.isEmpty else { return nil }

        // Admit one durable snapshot for the whole run. The visible preset may
        // still hold a stale value when an external edit has not been delivered
        // yet, so the run never builds requests from view state.
        let snapshotResult = Result { try context.settingsStore.loadSettings() }
        let controller = beginConversionRun(admittedSettings: try? snapshotResult.get())
        let task = Task { @MainActor in
            await performConversion(
                files: files,
                settingsSnapshot: snapshotResult,
                controller: controller
            )
        }
        conversionTask = task
        return task
    }

    private func queuedConversionFiles() -> [BatchAudioConversionFile] {
        rows.compactMap { row -> BatchAudioConversionFile? in
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
    }

    private func beginConversionRun(admittedSettings: AppSettings?) -> StopAfterCurrentController {
        let controller = StopAfterCurrentController()
        stopController = controller
        isCancelRequested = false
        deferredDurableSettings = nil
        activeBatchSettings = admittedSettings
        isConverting = true
        statusText = AudioConverterCopy.converting
        overallProgress = 0
        publishShellJobStatus()
        return controller
    }

    private func performConversion(
        files: [BatchAudioConversionFile],
        settingsSnapshot: Result<AppSettings, any Error>,
        controller: StopAfterCurrentController
    ) async -> [BatchAudioConversionOutcome] {
        context.diagnostics.scoped(to: .converter).log(.info, "Conversion started (files=\(files.count))")
        do {
            // Durable truth at admission wins over possibly stale view state.
            // This only mirrors the snapshot locally; it never writes back, so
            // a newer user edit elsewhere is not overwritten. The admitted
            // preset and queued names stay visible for the whole batch; later
            // durable edits defer until after the run.
            let settings = try settingsSnapshot.get()
            if settings.audioPreset != currentAudioPreset {
                currentAudioPreset = settings.audioPreset
            }
            refreshQueuedOutputNames(using: settings)
            let outcomes = try await batchUseCase.convert(
                files: files,
                settings: settings,
                stopController: controller,
                progress: { [weak self] update in
                    Task { @MainActor in
                        self?.apply(update)
                    }
                }
            )
            outcomes.forEach { apply($0.update) }
            overallProgress = outcomes.last?.overallProgress ?? overallProgress
            endConversionRun()
            convergeToLatestDurableSettings()
            let canceledCount = outcomes.filter { $0.status == .canceled }.count
            if canceledCount > 0 {
                let convertedCount = outcomes.filter(\.status.producedVerifiedWAV).count
                statusText = AudioConverterCopy.canceledSummary(converted: convertedCount, of: files.count)
            } else {
                refreshStatusText()
            }
            publishShellJobStatus()
            let failedCount = outcomes.filter { if case .failed = $0.status { true } else { false } }.count
            context.diagnostics.scoped(to: .converter).log(
                .info,
                "Conversion finished (files=\(outcomes.count), failed=\(failedCount), canceled=\(canceledCount))"
            )
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
            endConversionRun()
            convergeToLatestDurableSettings()
            statusText = error.localizedDescription
            publishShellJobStatus()
            context.diagnostics.scoped(to: .converter).log(.error, "Conversion failed: \(error.localizedDescription)")
            return []
        }
    }

    private func endConversionRun() {
        activeBatchSettings = nil
        isConverting = false
        isCancelRequested = false
        stopController = nil
        conversionTask = nil
    }

    /// The pane's "Stop After This File": the file in flight finishes, the rest are skipped.
    public func requestStopAfterCurrent() {
        stopController?.requestStopAfterCurrent()
    }

    /// The shell jobs-row "Cancel": stops the file in flight now (its temp output is
    /// removed) and cancels the rest. WAVs verified before the cancel are kept.
    public func cancelConversion() {
        guard isConverting, let conversionTask else { return }
        isCancelRequested = true
        conversionTask.cancel()
        context.diagnostics.scoped(to: .converter).log(.info, "Conversion cancel requested")
    }

    public func updateWAVPreset(sampleRate: Int, bitDepth: Int, channelMode: AudioChannelMode) {
        guard !isConverting else { return }
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
            var helperTools = try context.settingsStore.loadSettings().helperTools
            helperTools.ffmpeg = ffmpegURL

            switch await ffmpegHealthChecker.availability(settings: helperTools) {
            case .available:
                try context.settingsStore.updateSettings { settings in
                    settings.helperTools.ffmpeg = ffmpegURL
                }
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

    private func publishShellJobStatus() {
        let filename = rows.first(where: { $0.state == .converting })?.sourceURL.lastPathComponent
            ?? rows.first(where: { $0.state == .queued && $0.isConvertible })?.sourceURL.lastPathComponent
        let status = ConverterJobReporting.status(
            isConverting: isConverting,
            filename: filename,
            percent: overallProgress
        )
        context.jobStatusCenter.setExtraJob(
            sourceID: ShellJobExtraSourceID.converter,
            status: status,
            cancel: { [weak self] in
                Task { @MainActor in
                    self?.cancelConversion()
                }
            }
        )
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
        if let activeBatchSettings {
            return plannedOutputName(for: sourceURL, using: activeBatchSettings)
        }
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        return plannedOutputName(for: sourceURL, using: settings)
    }

    private func plannedOutputName(for sourceURL: URL, using settings: AppSettings) -> String {
        outputFileNamer.plannedOutputURL(
            for: settings.outputFolder.url,
            sourceURL: sourceURL,
            preset: settings.audioPreset,
            existingFileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        .lastPathComponent
    }

    private func refreshQueuedOutputNames() {
        if let activeBatchSettings {
            refreshQueuedOutputNames(using: activeBatchSettings)
            return
        }
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        refreshQueuedOutputNames(using: settings)
    }

    private func refreshQueuedOutputNames(using settings: AppSettings) {
        rows = rows.map { row in
            guard row.state == .queued, row.isConvertible else {
                return row
            }

            var updatedRow = row
            updatedRow.plannedOutputName = plannedOutputName(for: row.sourceURL, using: settings)
            return updatedRow
        }
    }

    /// Mirror a durable settings change (Settings pane or another writer). This
    /// only reads: it never writes back, so a newer user edit cannot be
    /// overwritten by stale view state. While a batch is active the visible
    /// preset and queued names stay aligned with the admitted snapshot; the
    /// change is deferred and converged after the run for the next batch.
    private func applyDurableSettingsChange(_ settings: AppSettings) {
        guard !isConverting else {
            deferredDurableSettings = settings
            return
        }
        if settings.audioPreset != currentAudioPreset {
            currentAudioPreset = settings.audioPreset
        }
        refreshQueuedOutputNames(using: settings)
    }

    /// After the active batch ends, show the latest durable settings so the
    /// next run admits them. Reads only; status and row outcomes are untouched.
    private func convergeToLatestDurableSettings() {
        let deferred = deferredDurableSettings
        deferredDurableSettings = nil
        let latest: AppSettings
        if let loaded = try? context.settingsStore.loadSettings() {
            latest = loaded
        } else if let deferred {
            latest = deferred
        } else {
            return
        }
        if latest.audioPreset != currentAudioPreset {
            currentAudioPreset = latest.audioPreset
        }
        refreshQueuedOutputNames(using: latest)
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
        publishShellJobStatus()
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
        case let .verifiedWithHandoffWarning(result, _):
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .verified,
                statusText: AudioConverterCopy.verifiedWithHandoffWarning,
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
        case .canceled:
            guard row.state == .queued || row.state == .converting else {
                return nil
            }
            return row.updated(
                state: .skipped,
                statusText: AudioConverterCopy.canceled,
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
        if rows.contains(where: {
            $0.state == .verified && $0.statusText == AudioConverterCopy.verifiedWithHandoffWarning
        }) {
            statusText = AudioConverterCopy.verifiedWithHandoffWarning
        } else if rows.contains(where: { $0.state == .verified }) {
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

    public static func sampleRateLabel(for sampleRate: Int) -> String {
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

    static func channelModeLabel(for channelMode: AudioChannelMode) -> String {
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
    public static let ready = "Queued"
    public static let converting = "Converting to Cubase-ready WAV"
    public static let verified = "Verified WAV ready"
    public static let verifiedWithHandoffWarning = "Verified WAV ready, but Output Inbox could not save the handoff."
    public static let unsupported = "This file type is not supported. Add M4A, MP3, WAV, AIFF, or FLAC instead."
    public static let missingFFmpeg = "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
    public static let verificationFailed = "WAV verification failed. The source file was left untouched; check the output preset and try again."
    public static let genericFailure = "Could not convert this file. Keep the source selected, review the row message, then try Convert to WAV again."
    public static let skipped = "Skipped"
    public static let canceled = "Canceled"
    public static let stopAfterThisFile = "Stop After This File"
    public static let stopAfterThisFileHelp = "Finishes the file that is converting, then skips the rest. Verified WAV files are kept."
    public static let chooseFFmpeg = "Choose FFmpeg"
    public static let selectedFFmpegMissing = "Selected FFmpeg could not be found. Choose FFmpeg, then pick the executable again."

    public static func selectedFFmpegUnusable(_ message: String) -> String {
        "Selected FFmpeg could not be used: \(message)"
    }

    public static func canceledSummary(converted: Int, of total: Int) -> String {
        "Canceled — \(converted) of \(total) \(total == 1 ? "file" : "files") converted"
    }
}

private extension BatchAudioConversionStatus {
    var producedVerifiedWAV: Bool {
        switch self {
        case .verified, .verifiedWithHandoffWarning:
            return true
        case .converting, .failed, .skipped, .canceled:
            return false
        }
    }
}
