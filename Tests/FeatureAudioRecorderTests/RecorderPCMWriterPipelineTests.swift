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
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeFloatBuffer(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        return buffer
    }
}

/// Builds real WAV writers whose Nth `writeBuffer` (counted across the take) throws.
final class FailingPCMWriterFactory: @unchecked Sendable {
    struct InjectedWriteFailure: LocalizedError {
        var errorDescription: String? { "The disk is full." }
    }

    private let lock = NSLock()
    private let failOnWrite: Int
    private var attempts = 0

    init(failOnWrite: Int) { self.failOnWrite = failOnWrite }

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
        try base.finalize(diagnostics: diagnostics)
    }
}

private final class ReportedWriteErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RecorderError] = []
    var errors: [RecorderError] { lock.withLock { stored } }
    func append(_ error: RecorderError) { lock.withLock { stored.append(error) } }
}
