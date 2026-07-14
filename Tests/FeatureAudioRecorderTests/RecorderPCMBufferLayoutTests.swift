import AVFAudio
import AudioToolbox
import CoreAudio
import XCTest
@testable import FeatureAudioRecorder

/// Deterministic coverage for `RecorderPCMBufferLayout`, the pure frame-count derivation
/// used to assign explicit `frameLength` to no-copy capture buffers. These tests use
/// hand-built `AudioBufferList`s and require no audio hardware or permission.
final class RecorderPCMBufferLayoutTests: XCTestCase {
    private let bytesPerSample: UInt32 = 4 // float32

    func testInterleavedBufferFrameCount() {
        let frames: UInt32 = 512
        let asbd = makeASBD(channels: 2, interleaved: true)
        let list = ManagedBufferList(bufferByteSizes: [Int(frames * asbd.mBytesPerFrame)], channelsPerBuffer: [2])

        let result = list.withUnsafePointer {
            RecorderPCMBufferLayout.frameCount(bufferList: $0, streamDescription: asbd)
        }
        XCTAssertEqual(result, AVAudioFrameCount(frames))
    }

    func testNonInterleavedBufferFrameCount() {
        let frames: UInt32 = 480
        let asbd = makeASBD(channels: 2, interleaved: false)
        let perChannelBytes = Int(frames * asbd.mBytesPerFrame) // bytesPerFrame == 4 per channel
        let list = ManagedBufferList(bufferByteSizes: [perChannelBytes, perChannelBytes], channelsPerBuffer: [1, 1])

        let result = list.withUnsafePointer {
            RecorderPCMBufferLayout.frameCount(bufferList: $0, streamDescription: asbd)
        }
        XCTAssertEqual(result, AVAudioFrameCount(frames))
    }

    func testZeroByteBufferIsStructuralNoData() {
        let asbd = makeASBD(channels: 2, interleaved: true)
        // A buffer that is present in the list but carries zero bytes / nil data must be
        // classified as structural no-data (nil), NOT as a zero-length valid buffer.
        let list = ManagedBufferList(bufferByteSizes: [0], channelsPerBuffer: [2])

        let result = list.withUnsafePointer {
            RecorderPCMBufferLayout.frameCount(bufferList: $0, streamDescription: asbd)
        }
        XCTAssertNil(result)
    }

    func testMismatchedChannelBufferSizesUsesShortestValidLength() {
        let asbd = makeASBD(channels: 2, interleaved: false)
        let shortFrames: UInt32 = 400
        let longFrames: UInt32 = 512
        let list = ManagedBufferList(
            bufferByteSizes: [Int(shortFrames * asbd.mBytesPerFrame), Int(longFrames * asbd.mBytesPerFrame)],
            channelsPerBuffer: [1, 1]
        )

        let result = list.withUnsafePointer {
            RecorderPCMBufferLayout.frameCount(bufferList: $0, streamDescription: asbd)
        }
        // The minimum positive frame count prevents reading a channel beyond its data.
        XCTAssertEqual(result, AVAudioFrameCount(shortFrames))
    }

    func testSilentNonEmptyPCMIsAccepted() {
        // A valid buffer whose sample values are all zero (silence) still contains frames
        // and bytes; it must be accepted, not treated as a dead capture path.
        let frames: UInt32 = 256
        let asbd = makeASBD(channels: 2, interleaved: true)
        let byteCount = Int(frames * asbd.mBytesPerFrame)
        let list = ManagedBufferList(bufferByteSizes: [byteCount], channelsPerBuffer: [2]) // zero-initialized memory

        let result = list.withUnsafePointer {
            RecorderPCMBufferLayout.frameCount(bufferList: $0, streamDescription: asbd)
        }
        XCTAssertEqual(result, AVAudioFrameCount(frames))

        let bytes = list.withUnsafePointer { RecorderPCMBufferLayout.usableByteCount(bufferList: $0) }
        XCTAssertEqual(bytes, Int64(byteCount))
    }

    func testNoCopyPCMBufferGetsExplicitFrameLengthFromDataBytes() throws {
        // End-to-end: derive frames from the raw list, apply them to a no-copy PCM buffer,
        // and confirm frameLength reflects the real byte payload (not a stale/zero value).
        let frames: UInt32 = 512
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        ))
        let asbd = format.streamDescription.pointee
        let list = ManagedBufferList(bufferByteSizes: [Int(frames * asbd.mBytesPerFrame)], channelsPerBuffer: [2])

        list.withUnsafePointer { pointer in
            guard let derived = RecorderPCMBufferLayout.frameCount(bufferList: pointer, streamDescription: asbd) else {
                XCTFail("Expected a positive frame count")
                return
            }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: pointer, deallocator: nil)
            let unwrapped = buffer!
            unwrapped.frameLength = min(derived, unwrapped.frameCapacity)
            XCTAssertEqual(unwrapped.frameLength, AVAudioFrameCount(frames))
        }
    }

    private func makeASBD(channels: UInt32, interleaved: Bool) -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = 48_000
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        asbd.mBitsPerChannel = 32
        asbd.mChannelsPerFrame = channels
        asbd.mFramesPerPacket = 1
        if interleaved {
            asbd.mBytesPerFrame = bytesPerSample * channels
            asbd.mBytesPerPacket = bytesPerSample * channels
        } else {
            asbd.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
            asbd.mBytesPerFrame = bytesPerSample
            asbd.mBytesPerPacket = bytesPerSample
        }
        return asbd
    }
}

/// Owns the backing memory for a hand-built `AudioBufferList` so tests can exercise the
/// layout helper against realistic buffers. Frees all allocations on deinit.
private final class ManagedBufferList {
    private let listPointer: UnsafeMutableAudioBufferListPointer
    private var allocations: [UnsafeMutableRawPointer] = []

    init(bufferByteSizes: [Int], channelsPerBuffer: [UInt32]) {
        let count = max(1, bufferByteSizes.count)
        listPointer = AudioBufferList.allocate(maximumBuffers: count)
        listPointer.count = bufferByteSizes.count
        for index in bufferByteSizes.indices {
            let size = bufferByteSizes[index]
            var audioBuffer = AudioBuffer()
            audioBuffer.mNumberChannels = channelsPerBuffer.indices.contains(index) ? channelsPerBuffer[index] : 1
            if size > 0 {
                let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
                memory.initializeMemory(as: UInt8.self, repeating: 0, count: size)
                allocations.append(memory)
                audioBuffer.mData = memory
                audioBuffer.mDataByteSize = UInt32(size)
            } else {
                audioBuffer.mData = nil
                audioBuffer.mDataByteSize = 0
            }
            listPointer[index] = audioBuffer
        }
    }

    deinit {
        allocations.forEach { $0.deallocate() }
        free(listPointer.unsafeMutablePointer)
    }

    func withUnsafePointer<R>(_ body: (UnsafePointer<AudioBufferList>) -> R) -> R {
        body(UnsafePointer(listPointer.unsafeMutablePointer))
    }
}
