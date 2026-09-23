import AppCore
import AVFAudio
import ScreenCaptureKit
import XCTest
@testable import FeatureAudioRecorder

final class RecorderPermissionTests: XCTestCase {
    func testIncompatibleMacOSVersion() {
        let adapter = CoreAudioTapAdapter()
        let compatible = adapter.isCompatibleMacOS()
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 14 {
            XCTAssertFalse(compatible)
        } else {
            XCTAssertTrue(compatible)
        }
    }

    // MARK: - Probe verdict

    func testProbeHearingItsOwnToneIsAuthorized() {
        let evidence = SystemAudioCapturePermissionEvidence(
            referenceSecondsRendered: 0.05,
            tapDeliveredNonZeroSample: true
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .authorized)
    }

    func testProbeReadingZerosWhileItsToneRendersIsBlocked() {
        let evidence = SystemAudioCapturePermissionEvidence(
            tapSecondsBeforeTone: 0.05,
            tapSecondsDuringWarmup: 0.2,
            tapSecondsObservedAfterWarmup: 0.4,
            referenceSecondsRendered: 0.7,
            referenceSecondsRenderedAfterWarmup: 0.45
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .blocked)
    }

    func testProbeWithoutTapFramesIsInconclusive() {
        // Empty IO buffers are the known route failure, not a permission signature.
        let evidence = SystemAudioCapturePermissionEvidence(
            referenceSecondsRendered: 1.3,
            referenceSecondsRenderedAfterWarmup: 1,
            tapStructuralNoDataCallbacks: 105
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .inconclusive)
    }

    func testProbeWithStructuralGapsAfterWarmupIsInconclusive() {
        let evidence = SystemAudioCapturePermissionEvidence(
            tapSecondsDuringWarmup: 0.2,
            tapSecondsObservedAfterWarmup: 0.5,
            referenceSecondsRendered: 0.9,
            referenceSecondsRenderedAfterWarmup: 0.5,
            tapStructuralNoDataCallbacks: 1,
            tapStructuralNoDataCallbacksAfterWarmup: 1
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .inconclusive)
    }

    func testProbeWhoseToneStoppedRenderingIsInconclusive() {
        // Zeros only prove a block while the tone is provably rendering into the tap.
        let evidence = SystemAudioCapturePermissionEvidence(
            tapSecondsDuringWarmup: 0.2,
            tapSecondsObservedAfterWarmup: 1,
            referenceSecondsRendered: 0.25,
            referenceSecondsRenderedAfterWarmup: 0.05
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .inconclusive)
    }

    func testProbeWithTooLittleSilentTapAudioAfterWarmupIsInconclusive() {
        // Startup zeros before the tone and during warm-up never count.
        let evidence = SystemAudioCapturePermissionEvidence(
            tapSecondsBeforeTone: 1,
            tapSecondsDuringWarmup: 0.2,
            tapSecondsObservedAfterWarmup: 0.1,
            referenceSecondsRendered: 1,
            referenceSecondsRenderedAfterWarmup: 0.8
        )
        XCTAssertEqual(SystemAudioCapturePermissionClassifier.verdict(for: evidence), .inconclusive)
    }

    // MARK: - ScreenCaptureKit authorization failures

    func testScreenCaptureKitUserDeclinedIsAPermissionFailure() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        XCTAssertTrue(ScreenCaptureKitAudioSession.isCapturePermissionFailure(error, screenCaptureAccessGranted: { true }))
    }

    func testOtherScreenCaptureKitFailureWithAccessGrantedIsNotAPermissionFailure() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noCaptureSource.rawValue)
        XCTAssertFalse(ScreenCaptureKitAudioSession.isCapturePermissionFailure(error, screenCaptureAccessGranted: { true }))
    }

    func testScreenCaptureKitFailureWithFailedPreflightIsAPermissionFailure() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noCaptureSource.rawValue)
        XCTAssertTrue(ScreenCaptureKitAudioSession.isCapturePermissionFailure(error, screenCaptureAccessGranted: { false }))
    }

    // MARK: - Digital silence detection

    func testExactZeroFloatBufferIsDigitalSilence() throws {
        let buffer = try makeFloatBuffer(frames: 256)
        XCTAssertFalse(RecorderPCMWriterPipeline.containsNonZeroSample(buffer))
    }

    func testQuietFloatSampleIsNotDigitalSilence() throws {
        let buffer = try makeFloatBuffer(frames: 256)
        buffer.floatChannelData![1][200] = 0.000_01
        XCTAssertTrue(RecorderPCMWriterPipeline.containsNonZeroSample(buffer))
    }

    func testSamplesBeyondFrameLengthAreIgnored() throws {
        let buffer = try makeFloatBuffer(frames: 256)
        buffer.floatChannelData![0][255] = 0.5
        buffer.frameLength = 128
        XCTAssertFalse(RecorderPCMWriterPipeline.containsNonZeroSample(buffer))
    }

    func testInterleavedInt16NonZeroSampleIsDetected() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        let samples = try XCTUnwrap(buffer.int16ChannelData)[0]
        for index in 0..<128 { samples[index] = 0 }
        XCTAssertFalse(RecorderPCMWriterPipeline.containsNonZeroSample(buffer))
        samples[127] = 1
        XCTAssertTrue(RecorderPCMWriterPipeline.containsNonZeroSample(buffer))
    }

    func testDigitalSilenceFlagClearsOnceRealAudioWasWritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence-guard-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try RecorderPCMWriterPipeline(
            outputURL: url,
            preset: .cubaseDefault,
            diagnostics: RecorderSessionDiagnostics(),
            onLevel: { _ in }
        )
        pipeline.activate(generation: 1)
        let buffer = try makeFloatBuffer(frames: 256)
        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))
        XCTAssertTrue(pipeline.containsOnlyDigitalSilence)

        buffer.floatChannelData![0][0] = 0.2
        XCTAssertTrue(pipeline.accept(generation: 1, sourceFormat: buffer.format, buffer: buffer, inputByteCount: 2_048))

        XCTAssertFalse(pipeline.containsOnlyDigitalSilence)
        XCTAssertEqual(try pipeline.finalize().frameCount, 512)
    }

    private func makeFloatBuffer(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<Int(frames) { channels[channel][frame] = 0 }
        }
        return buffer
    }
}
