@preconcurrency import AVFAudio
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Replaceable ScreenCaptureKit audio-only backend used after Core Audio cannot become healthy.
final class ScreenCaptureKitAudioSession: NSObject, @unchecked Sendable, RecorderCaptureBackend {
    let identity = RecorderCaptureBackendIdentity.screenCaptureKit

    private let lock = NSLock()
    private let sampleQueue = DispatchQueue(label: "NikoMusicHub.ScreenCaptureKitAudioSession.samples", qos: .userInitiated)
    private var stream: SCStream?
    private var callbacks: RecorderBackendCallbacks?
    private var generation = 0
    private var running = false
    private var stopping = false

    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw RecorderError.apiError("ScreenCaptureKit found no display to anchor system-audio capture")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.showsCursor = false
        configuration.queueDepth = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)

        let activeStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try activeStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        lock.withLock {
            self.generation = generation
            self.callbacks = callbacks
            stream = activeStream
            running = true
            stopping = false
        }
        do {
            try await activeStream.startCapture()
        } catch {
            lock.withLock {
                running = false
                stream = nil
                self.callbacks = nil
            }
            try? activeStream.removeStreamOutput(self, type: .audio)
            throw error
        }
    }

    func stop() async {
        let activeStream = lock.withLock { () -> SCStream? in
            guard !stopping else { return nil }
            stopping = true
            running = false
            let value = stream
            stream = nil
            callbacks = nil
            return value
        }
        guard let activeStream else { return }
        try? await activeStream.stopCapture()
        try? activeStream.removeStreamOutput(self, type: .audio)
        lock.withLock { stopping = false }
    }

    private func handle(_ sampleBuffer: CMSampleBuffer) {
        let snapshot = lock.withLock { () -> (Bool, Int, RecorderBackendCallbacks?) in
            (running, generation, callbacks)
        }
        guard snapshot.0, let callbacks = snapshot.2 else { return }
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        let asbd = asbdPointer.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: asbd) else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }

        // Configuration requests stereo, so storage for an AudioBufferList plus one extra
        // AudioBuffer covers both interleaved (1) and noninterleaved (2) layouts.
        let allocationSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: allocationSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let audioBufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: allocationSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr,
              let layoutFrames = RecorderPCMBufferLayout.frameCount(
                  bufferList: UnsafePointer(audioBufferList),
                  streamDescription: asbd
              ),
              let pcm = AVAudioPCMBuffer(
                  pcmFormat: sourceFormat,
                  bufferListNoCopy: UnsafePointer(audioBufferList),
                  deallocator: nil
              )
        else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        pcm.frameLength = min(AVAudioFrameCount(sampleCount), min(layoutFrames, pcm.frameCapacity))
        let bytes = RecorderPCMBufferLayout.usableByteCount(bufferList: UnsafePointer(audioBufferList))
        guard pcm.frameLength > 0, bytes > 0 else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        callbacks.onMetadata(RecorderBackendMetadata(
            outputDeviceUID: "screen-capture-kit",
            sourceSampleRate: sourceFormat.sampleRate,
            sourceChannelCount: Int(sourceFormat.channelCount)
        ))
        _ = callbacks.onPCM(snapshot.1, sourceFormat, pcm, bytes)
        _ = retainedBlockBuffer // Retains borrowed audio storage through the synchronous write.
    }
}

extension ScreenCaptureKitAudioSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handle(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let callback = lock.withLock { () -> RecorderBackendCallbacks? in
            guard running, !stopping else { return nil }
            running = false
            return callbacks
        }
        callback?.onFailure("screen-capture-kit stopped: \(error.localizedDescription)")
    }
}

private extension AVAudioFormat {
    convenience init?(streamDescription: AudioStreamBasicDescription) {
        var description = streamDescription
        self.init(streamDescription: &description)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
