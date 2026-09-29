import AppCore
@preconcurrency import AVFAudio
import Foundation

enum RecorderCaptureBackendIdentity: String, Sendable {
    case coreAudio = "core-audio"
    case screenCaptureKit = "screen-capture-kit"
}

struct RecorderBackendMetadata: Sendable {
    let outputDeviceUID: String
    let sourceSampleRate: Double
    let sourceChannelCount: Int
}

/// The file side of the pipeline. `WAVRecorderWriter` is the only production writer;
/// tests substitute one that fails on demand.
protocol RecorderPCMWriting: AnyObject, Sendable {
    var processingFormat: AVAudioFormat { get }
    var writtenFrameCount: Int64 { get }
    var currentTime: TimeInterval { get }
    func writeBuffer(_ buffer: AVAudioPCMBuffer) throws
    func finalize(diagnostics: RecorderDiagnostics?) throws -> RecorderResult
}

extension WAVRecorderWriter: RecorderPCMWriting {}

typealias RecorderPCMWriterFactory = @Sendable (URL, AudioPreset) throws -> any RecorderPCMWriting

let wavRecorderWriterFactory: RecorderPCMWriterFactory = { try WAVRecorderWriter(outputURL: $0, preset: $1) }

/// One serialized conversion-and-writing boundary for the complete logical take.
/// Backend replacement changes only the accepted generation; it never replaces the writer.
final class RecorderPCMWriterPipeline: @unchecked Sendable {
    private enum FinalizationState {
        case active
        case completed(RecorderResult)
        case failed(RecorderError)
    }

    private let lock = NSLock()
    private let writer: any RecorderPCMWriting
    private let outputURL: URL
    private let diagnostics: RecorderSessionDiagnostics
    private let onLevel: @Sendable (RecorderAudioLevel) -> Void
    private let onWriteError: @Sendable (RecorderError) -> Void
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?
    private var acceptedGeneration = 0
    private var finalizationState: FinalizationState = .active
    private var capturedNonZeroSample = false
    private var failedWrite: RecorderError?
    private var keptPartialTake = false

    init(
        outputURL: URL,
        preset: AudioPreset,
        diagnostics: RecorderSessionDiagnostics,
        makeWriter: RecorderPCMWriterFactory = wavRecorderWriterFactory,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onWriteError: @escaping @Sendable (RecorderError) -> Void = { _ in }
    ) throws {
        self.outputURL = outputURL
        self.writer = try makeWriter(outputURL, preset)
        self.diagnostics = diagnostics
        self.onLevel = onLevel
        self.onWriteError = onWriteError
        diagnostics.setOutputSampleRate(writer.processingFormat.sampleRate)
    }

    var processingFormat: AVAudioFormat { writer.processingFormat }

    func activate(generation: Int) {
        lock.lock()
        acceptedGeneration = generation
        converter = nil
        converterSourceFormat = nil
        lock.unlock()
    }

    /// Converts and writes synchronously so a backend callback's borrowed PCM storage stays valid.
    /// Returns true only after nonempty PCM was successfully written.
    @discardableResult
    func accept(
        generation: Int,
        sourceFormat: AVAudioFormat,
        buffer: AVAudioPCMBuffer,
        inputByteCount: Int64
    ) -> Bool {
        lock.lock()
        guard case .active = finalizationState,
              generation == acceptedGeneration,
              buffer.frameLength > 0,
              inputByteCount > 0
        else {
            lock.unlock()
            return false
        }

        diagnostics.recordInput(
            bytes: inputByteCount,
            frames: Int64(buffer.frameLength),
            sourceFormat: sourceFormat
        )

        if converterSourceFormat == nil || !formatsMatch(converterSourceFormat!, sourceFormat) {
            converter = AVAudioConverter(from: sourceFormat, to: writer.processingFormat)
            converterSourceFormat = sourceFormat
        }
        guard let converter else {
            diagnostics.recordConverterError()
            lock.unlock()
            return false
        }

        let ratio = writer.processingFormat.sampleRate / sourceFormat.sampleRate
        let capacity = max(1, AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32)
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: writer.processingFormat,
            frameCapacity: capacity
        ) else {
            diagnostics.recordConverterError()
            lock.unlock()
            return false
        }

        let inputState = RecorderConverterInputState(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            inputState.provide(outStatus: outStatus)
        }
        guard conversionError == nil,
              status != .error,
              converted.frameLength > 0
        else {
            diagnostics.recordConverterError()
            lock.unlock()
            return false
        }
        diagnostics.recordConvertedFrames(Int64(converted.frameLength))

        do {
            try writer.writeBuffer(converted)
        } catch {
            // ENG-11: the first failed write ends the take. Later buffers are rejected by
            // the state guard above, so the error is reported exactly once, right now.
            // Audio that already reached disk is closed and kept, never deleted: the
            // take cannot be recorded again.
            diagnostics.recordWriteError()
            let keepsAudio = closeKeepingWrittenAudio()
            let failure = RecorderError.writeError(
                "Writing to disk failed, so the recording stopped. \(error.localizedDescription) "
                    + (keepsAudio ? Self.keptPartialTakeNote(outputURL) + " " : "")
                    + "Diagnostics: \(diagnostics.snapshot().summary)."
            )
            finalizationState = .failed(failure)
            failedWrite = failure
            lock.unlock()
            if !keepsAudio {
                try? FileManager.default.removeItem(at: outputURL)
            }
            onWriteError(failure)
            return false
        }
        diagnostics.setWrittenFrameCount(writer.writtenFrameCount)
        if !capturedNonZeroSample, Self.containsNonZeroSample(buffer) {
            capturedNonZeroSample = true
        }
        let level = RecorderAudioLevel(
            peak: Self.meterPeak(from: buffer),
            average: Self.meterAverage(from: buffer),
            elapsedTime: writer.currentTime
        )
        lock.unlock()
        onLevel(level)
        return true
    }

    func finalize() throws -> RecorderResult {
        lock.lock()
        defer { lock.unlock() }
        switch finalizationState {
        case .completed(let result):
            return result
        case .failed(let error):
            throw error
        case .active:
            break
        }

        let snapshot = diagnostics.snapshot()
        guard writer.writtenFrameCount > 0 else {
            let error = RecorderError.noAudioCaptured(
                "The recorder tried both system-audio capture methods, but macOS did not deliver audio frames. "
                    + "Start audio playback and try again. If it keeps happening, allow Niko Music Hub in System Settings → Privacy & Security → Screen & System Audio Recording. Diagnostics: \(snapshot.summary)."
            )
            finalizationState = .failed(error)
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        do {
            let result = try writer.finalize(diagnostics: snapshot)
            finalizationState = .completed(result)
            return result
        } catch {
            // Frames are on disk (guarded above), so the file is kept for recovery.
            keptPartialTake = true
            let message = "\(error.localizedDescription) \(Self.keptPartialTakeNote(outputURL))"
            let mapped = RecorderError.writeError(message)
            finalizationState = .failed(mapped)
            throw mapped
        }
    }

    /// Called with the lock held after a failed write. Closes the file so the WAV
    /// header covers the frames already written; false when there is nothing to keep.
    private func closeKeepingWrittenAudio() -> Bool {
        guard writer.writtenFrameCount > 0 else { return false }
        _ = try? writer.finalize(diagnostics: nil)
        keptPartialTake = true
        return true
    }

    /// Error-copy suffix naming where a failed take's audio was kept.
    static func keptPartialTakeNote(_ url: URL) -> String {
        "The audio recorded before the error was kept, possibly incomplete, at \(url.path)."
    }

    /// Capture ended on its own (route loss with no working fallback). Keep the
    /// take when audio already reached disk: finalizing caches the result, so the
    /// follow-up `stop()` hands the recording to the user instead of an error.
    /// Only an empty take is discarded.
    func endAfterCaptureLoss(error: RecorderError) {
        lock.lock()
        let hasAudio = writer.writtenFrameCount > 0
        lock.unlock()
        if hasAudio, (try? finalize()) != nil {
            return
        }
        abort(error: error)
    }

    /// The write error that ended the take, if a write failed.
    var writeFailure: RecorderError? {
        lock.withLock { failedWrite }
    }

    /// True until a written buffer carried at least one nonzero sample. A take that is
    /// exact digital silence is what a Core Audio tap delivers when macOS withholds
    /// system-audio capture, and also what it delivers when nothing is playing.
    var containsOnlyDigitalSilence: Bool {
        lock.withLock { !capturedNonZeroSample }
    }

    /// Scans the valid frames byte-for-byte. Integer and float PCM silence is all-zero
    /// bytes; a format this cannot vouch for counts as audio so it never looks silent.
    static func containsNonZeroSample(_ buffer: AVAudioPCMBuffer) -> Bool {
        let format = buffer.format
        switch format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32:
            break
        default:
            return true
        }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let validBytes = Int(buffer.frameLength) * bytesPerFrame
        guard validBytes > 0 else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: buffer.audioBufferList)
        )
        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            let count = min(validBytes, Int(audioBuffer.mDataByteSize))
            let bytes = UnsafeRawBufferPointer(start: data, count: count)
            if bytes.contains(where: { $0 != 0 }) { return true }
        }
        return false
    }

    func abort(
        error: RecorderError = .noAudioCaptured("Audio capture stopped before any audio could be written.")
    ) {
        lock.lock()
        if case .active = finalizationState {
            finalizationState = .failed(error)
        }
        let keepsAudio = keptPartialTake
        lock.unlock()
        guard !keepsAudio else { return }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private static func meterPeak(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        return min(peak, 1)
    }

    private static func meterAverage(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let sampleCount = Int(buffer.frameLength) * Int(buffer.format.channelCount)
        guard sampleCount > 0 else { return 0 }
        var sum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                sum += abs(channels[channel][frame])
            }
        }
        return min(sum / Float(sampleCount), 1)
    }
}

/// AVAudioConverter invokes its input block synchronously while the pipeline lock is held.
/// The unchecked conformance is limited to that serialized conversion boundary.
private final class RecorderConverterInputState: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var provided = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !provided else {
            outStatus.pointee = .noDataNow
            return nil
        }
        provided = true
        outStatus.pointee = .haveData
        return buffer
    }
}

final class RecorderSessionDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var selectedBackend = ""
    private var attemptedBackends: [String] = []
    private var coreAudioRebuildCount = 0
    private var screenCaptureKitFallbackCount = 0
    private var routeChangeCount = 0
    private var startupTimeoutCount = 0
    private var outputDeviceUID = ""
    private var sourceSampleRate = 0.0
    private var sourceChannelCount = 0
    private var outputSampleRate = 0.0
    private var ioCallbackCount = 0
    private var inputBufferCallbackCount = 0
    private var zeroBufferCallbackCount = 0
    private var inputByteCount: Int64 = 0
    private var inputFrameCount: Int64 = 0
    private var convertedFrameCount: Int64 = 0
    private var writtenFrameCount: Int64 = 0
    private var converterErrorCount = 0
    private var writeErrorCount = 0

    func recordAttempt(_ backend: RecorderCaptureBackendIdentity) {
        lock.withLock { attemptedBackends.append(backend.rawValue) }
    }

    func select(_ backend: RecorderCaptureBackendIdentity) {
        lock.withLock { selectedBackend = backend.rawValue }
    }

    func recordCoreAudioRebuild() { lock.withLock { coreAudioRebuildCount += 1 } }
    func recordScreenCaptureKitFallback() { lock.withLock { screenCaptureKitFallbackCount += 1 } }
    func recordRouteChange() { lock.withLock { routeChangeCount += 1 } }
    func recordStartupTimeout() { lock.withLock { startupTimeoutCount += 1 } }
    func recordStructuralNoData() {
        lock.withLock {
            ioCallbackCount += 1
            zeroBufferCallbackCount += 1
        }
    }

    func recordMetadata(_ metadata: RecorderBackendMetadata) {
        lock.withLock {
            outputDeviceUID = metadata.outputDeviceUID
            sourceSampleRate = metadata.sourceSampleRate
            sourceChannelCount = metadata.sourceChannelCount
        }
    }

    func setOutputSampleRate(_ rate: Double) { lock.withLock { outputSampleRate = rate } }
    func recordInput(bytes: Int64, frames: Int64, sourceFormat: AVAudioFormat) {
        lock.withLock {
            ioCallbackCount += 1
            inputBufferCallbackCount += 1
            inputByteCount += max(0, bytes)
            inputFrameCount += max(0, frames)
            sourceSampleRate = sourceFormat.sampleRate
            sourceChannelCount = Int(sourceFormat.channelCount)
        }
    }
    func recordConvertedFrames(_ frames: Int64) { lock.withLock { convertedFrameCount += max(0, frames) } }
    func setWrittenFrameCount(_ frames: Int64) { lock.withLock { writtenFrameCount = max(0, frames) } }
    func recordConverterError() { lock.withLock { converterErrorCount += 1 } }
    func recordWriteError() { lock.withLock { writeErrorCount += 1 } }

    func snapshot() -> RecorderDiagnostics {
        lock.withLock {
            RecorderDiagnostics(
                selectedBackend: selectedBackend,
                attemptedBackends: attemptedBackends,
                coreAudioRebuildCount: coreAudioRebuildCount,
                screenCaptureKitFallbackCount: screenCaptureKitFallbackCount,
                routeChangeCount: routeChangeCount,
                startupTimeoutCount: startupTimeoutCount,
                outputDeviceUID: outputDeviceUID,
                tapSampleRate: sourceSampleRate,
                tapChannelCount: sourceChannelCount,
                captureSampleRate: sourceSampleRate,
                outputSampleRate: outputSampleRate,
                ioCallbackCount: ioCallbackCount,
                inputBufferCallbackCount: inputBufferCallbackCount,
                outputBufferCallbackCount: 0,
                zeroBufferCallbackCount: zeroBufferCallbackCount,
                inputByteCount: inputByteCount,
                inputFrameCount: inputFrameCount,
                convertedFrameCount: convertedFrameCount,
                writtenFrameCount: writtenFrameCount,
                converterErrorCount: converterErrorCount,
                writeErrorCount: writeErrorCount
            )
        }
    }
}
