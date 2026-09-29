import AppCore
import AVFAudio
import XCTest
@testable import FeatureAudioRecorder

final class RecorderPCMWriterPipelineTests: XCTestCase {
    func testFirstWriteErrorIsReportedOnceImmediately() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-write-error-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writers = FailingPCMWriterFactory(failOnWrite: 2)
        let reported = ReportedWriteErrors()
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: writers.make,
            onLevel: { _ in },
            onWriteError: { reported.append($0) }
        )
        pipeline.activate(generation: 1)
        let buffer = try makeFloatBuffer(frames: 256)

        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertTrue(reported.errors.isEmpty)

        XCTAssertFalse(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertEqual(reported.errors.count, 1, "the failing write reports before accept returns")
        guard case .writeError = reported.errors.first else {
            return XCTFail("Expected writeError, got \(String(describing: reported.errors.first))")
        }

        for _ in 0..<3 {
            XCTAssertFalse(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        }
        XCTAssertEqual(reported.errors.count, 1, "later buffers never report again")
        XCTAssertEqual(writers.writeAttempts, 2, "nothing is written after the first failure")
        XCTAssertThrowsError(try pipeline.finalize()) { error in
            XCTAssertEqual(error as? RecorderError, reported.errors.first)
        }
    }

    func testLateWriteErrorKeepsTheAudioAlreadyWritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-partial-take-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writers = FailingPCMWriterFactory(failOnWrite: 2)
        let reported = ReportedWriteErrors()
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: writers.make,
            onLevel: { _ in },
            onWriteError: { reported.append($0) }
        )
        pipeline.activate(generation: 1)
        let buffer = try makeRampBuffer(frames: 256, startingAt: 0)

        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertFalse(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertThrowsError(try pipeline.finalize())
        pipeline.abort()

        guard case .writeError(let message) = reported.errors.first else {
            return XCTFail("Expected writeError, got \(String(describing: reported.errors.first))")
        }
        XCTAssertTrue(message.contains(url.path), "the error says where the audio was kept")
        try assertRetainedSamplesMatchFedRamp(url, frames: 256)
    }

    func testFinalizeErrorAfterWrittenAudioKeepsTheTakeAndNamesItsPath() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-finalize-error-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writers = FailingPCMWriterFactory(finalize: .throwsAfterClosingFile)
        let reported = ReportedWriteErrors()
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: writers.make,
            onLevel: { _ in },
            onWriteError: { reported.append($0) }
        )
        pipeline.activate(generation: 1)
        let first = try makeRampBuffer(frames: 256, startingAt: 0)
        let second = try makeRampBuffer(frames: 256, startingAt: 256)
        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: first.format, buffer: first, inputByteCount: 2_048))
        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: second.format, buffer: second, inputByteCount: 2_048))

        var thrown: RecorderError?
        XCTAssertThrowsError(try pipeline.finalize()) { thrown = $0 as? RecorderError }
        guard case .writeError(let message)? = thrown else {
            return XCTFail("Expected writeError, got \(String(describing: thrown))")
        }
        XCTAssertTrue(message.contains("The file could not be closed."), message)
        XCTAssertTrue(message.contains(url.path), "the error says where the audio was kept")
        XCTAssertThrowsError(try pipeline.finalize(), "a failed take never turns into a result on a second ask") {
            XCTAssertEqual($0 as? RecorderError, thrown)
        }
        pipeline.abort()
        XCTAssertTrue(reported.errors.isEmpty, "finalize errors reach the caller, not the write-error hook")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "abort must not delete the kept take")
        try assertRetainedSamplesMatchFedRamp(url, frames: 512)
    }

    func testFinalizeErrorThatLeavesTheFileOpenStillKeepsEveryWrittenFrame() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-finalize-open-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writers = FailingPCMWriterFactory(finalize: .throwsLeavingFileOpen)
        var pipeline: RecorderPCMWriterPipeline? = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: writers.make,
            onLevel: { _ in }
        )
        pipeline?.activate(generation: 1)
        let buffer = try makeRampBuffer(frames: 256, startingAt: 0)
        XCTAssertEqual(pipeline?.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048), true)

        XCTAssertThrowsError(try pipeline?.finalize()) { error in
            guard case .writeError(let message)? = error as? RecorderError else {
                return XCTFail("Expected writeError, got \(error)")
            }
            XCTAssertTrue(message.contains(url.path), message)
        }
        pipeline?.abort()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "abort must not delete the kept take")
        // Releasing the pipeline releases the writer, which closes the WAV header.
        pipeline = nil
        try assertRetainedSamplesMatchFedRamp(url, frames: 256)
    }

    func testCaptureLossWithFailingFinalizeStillKeepsTheWrittenAudio() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-loss-finalize-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: FailingPCMWriterFactory(finalize: .throwsAfterClosingFile).make,
            onLevel: { _ in }
        )
        pipeline.activate(generation: 1)
        let buffer = try makeRampBuffer(frames: 256, startingAt: 0)
        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))

        pipeline.endAfterCaptureLoss(error: .noAudioCaptured("The route was lost."))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "route loss must not delete audio that reached disk")
        XCTAssertThrowsError(try pipeline.finalize()) { error in
            guard case .writeError(let message)? = error as? RecorderError else {
                return XCTFail("Expected writeError, got \(error)")
            }
            XCTAssertTrue(message.contains(url.path), message)
        }
        try assertRetainedSamplesMatchFedRamp(url, frames: 256)
    }

    func testFirstWriteErrorLeavesNoEmptyFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-empty-take-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            makeWriter: FailingPCMWriterFactory(failOnWrite: 1).make,
            onLevel: { _ in }
        )
        pipeline.activate(generation: 1)
        let buffer = try makeFloatBuffer(frames: 256)

        XCTAssertFalse(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertThrowsError(try pipeline.finalize())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeFloatBuffer(frames: AVAudioFrameCount, value: Float = 0) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frames) { channels[channel][frame] = value }
            }
        }
        return buffer
    }

    /// Distinct per-channel PCM whose every value is exactly representable in 24-bit
    /// integer PCM, so a read-back can be compared for equality with what was fed.
    private func makeRampBuffer(frames: AVAudioFrameCount, startingAt offset: Int) throws -> AVAudioPCMBuffer {
        let buffer = try makeFloatBuffer(frames: frames)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(frames) {
                channels[channel][frame] = Self.rampValue(frame: offset + frame, channel: channel)
            }
        }
        return buffer
    }

    private static func rampValue(frame: Int, channel: Int) -> Float {
        Float((frame % 64) + 1 + channel * 64) / 256
    }

    private func readSamples(_ url: URL) throws -> (frames: Int, channels: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(frames, 1)))
        try file.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData)
        let channels = (0..<Int(file.processingFormat.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
        }
        return (Int(buffer.frameLength), channels)
    }

    private func assertRetainedSamplesMatchFedRamp(_ url: URL, frames expected: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let kept = try readSamples(url)
        XCTAssertEqual(kept.frames, expected, "the kept file holds exactly the frames fed before the failure", file: file, line: line)
        for (channel, samples) in kept.channels.enumerated() {
            let fed = (0..<expected).map { Self.rampValue(frame: $0, channel: channel) }
            XCTAssertEqual(samples, fed, "channel \(channel) equals the fed PCM", file: file, line: line)
        }
    }
}

/// Builds real WAV writers whose Nth `writeBuffer` (counted across the take) throws.
final class FailingPCMWriterFactory: @unchecked Sendable {
    struct InjectedWriteFailure: LocalizedError {
        var errorDescription: String? { "The disk is full." }
    }

    /// What `finalize` does on top of the real writer.
    enum FinalizeFault {
        case none
        /// The real writer closes the file, then the close is reported as failed.
        case throwsAfterClosingFile
        /// The close fails before the real writer released the file.
        case throwsLeavingFileOpen
    }

    struct InjectedFinalizeFailure: LocalizedError {
        var errorDescription: String? { "The file could not be closed." }
    }

    private let lock = NSLock()
    private let failOnWrite: Int
    let finalizeFault: FinalizeFault
    private var attempts = 0

    init(failOnWrite: Int = .max, finalize: FinalizeFault = .none) {
        self.failOnWrite = failOnWrite
        self.finalizeFault = finalize
    }

    var writeAttempts: Int { lock.withLock { attempts } }

    var make: RecorderPCMWriterFactory {
        { [self] url, preset in
            FailingPCMWriter(base: try WAVRecorderWriter(outputURL: url, preset: preset), factory: self)
        }
    }

    fileprivate func nextWriteFails() -> Bool {
        lock.withLock {
            attempts += 1
            return attempts >= failOnWrite
        }
    }
}

private final class FailingPCMWriter: RecorderPCMWriting, @unchecked Sendable {
    private let base: WAVRecorderWriter
    private let factory: FailingPCMWriterFactory

    init(base: WAVRecorderWriter, factory: FailingPCMWriterFactory) {
        self.base = base
        self.factory = factory
    }

    var processingFormat: AVAudioFormat { base.processingFormat }
    var writtenFrameCount: Int64 { base.writtenFrameCount }
    var currentTime: TimeInterval { base.currentTime }

    func writeBuffer(_ buffer: AVAudioPCMBuffer) throws {
        if factory.nextWriteFails() { throw FailingPCMWriterFactory.InjectedWriteFailure() }
        try base.writeBuffer(buffer)
    }

    func finalize(diagnostics: RecorderDiagnostics?) throws -> RecorderResult {
        switch factory.finalizeFault {
        case .none:
            return try base.finalize(diagnostics: diagnostics)
        case .throwsAfterClosingFile:
            _ = try base.finalize(diagnostics: diagnostics)
            throw FailingPCMWriterFactory.InjectedFinalizeFailure()
        case .throwsLeavingFileOpen:
            throw FailingPCMWriterFactory.InjectedFinalizeFailure()
        }
    }
}

private final class ReportedWriteErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RecorderError] = []
    var errors: [RecorderError] { lock.withLock { stored } }
    func append(_ error: RecorderError) { lock.withLock { stored.append(error) } }
}
