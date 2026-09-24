import AudioToolbox
import CoreAudio
import Foundation

/// Where the tap's audio sits in the input `AudioBufferList` of the recorder's private
/// aggregate device.
///
/// The aggregate's main sub-device is the output device (it clocks the IO proc), and an
/// output device can have input streams of its own: a Universal Audio Thunderbolt exposes
/// one 10-channel input stream, BlackHole or a Pro Tools bridge a loopback. The aggregate
/// presents the sub-device's input streams first and the tap's streams after them; on a
/// UAD2 its `kAudioDevicePropertyStreamConfiguration` (input) is `[10, 2]`, and the tap
/// stream's starting channel is 11. The HAL gives no stream a positive tap identity (the
/// aggregate owns all of them, none has a name or terminal type, the tap owns no stream
/// objects), so the layout is proven by composition instead: the aggregate's input streams
/// must be exactly the output device's input streams followed by streams shaped like the
/// tap's format. Anything else fails the Core Audio attempt rather than guessing, since a
/// wrong guess records the interface's microphones instead of system audio.
struct SystemAudioTapInputLayout: Equatable, Sendable {
    /// Buffers in every IO cycle's input list.
    let totalBufferCount: Int
    /// The tap's buffers within that list.
    let tapBuffers: Range<Int>

    static func resolve(
        aggregateInputChannels: [UInt32],
        outputDeviceInputChannels: [UInt32],
        tapFormat: AudioStreamBasicDescription
    ) throws -> SystemAudioTapInputLayout {
        let tapStreams = expectedTapStreams(for: tapFormat)
        guard !tapStreams.isEmpty,
              aggregateInputChannels == outputDeviceInputChannels + tapStreams
        else {
            let shape = (tapFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 ? "deinterleaved" : "interleaved"
            throw RecorderError.apiError(
                "Unrecognized Core Audio tap stream layout: aggregate inputs \(aggregateInputChannels), "
                    + "output device inputs \(outputDeviceInputChannels), "
                    + "tap \(tapFormat.mChannelsPerFrame) ch \(shape)"
            )
        }
        let start = outputDeviceInputChannels.count
        return SystemAudioTapInputLayout(
            totalBufferCount: aggregateInputChannels.count,
            tapBuffers: start..<aggregateInputChannels.count
        )
    }

    /// Channels per buffer the tap's format occupies: one buffer for interleaved audio,
    /// one mono buffer per channel otherwise.
    private static func expectedTapStreams(for format: AudioStreamBasicDescription) -> [UInt32] {
        let channels = format.mChannelsPerFrame
        guard channels > 0 else { return [] }
        if (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 {
            return Array(repeating: 1, count: Int(channels))
        }
        return [channels]
    }
}

/// Presents only the tap's buffers of an IO cycle, through a list allocated once per
/// session start so the IO thread never allocates. Used only from the session's serial
/// IO queue; the view is valid until the next cycle.
final class SystemAudioTapInputSelector: @unchecked Sendable {
    let layout: SystemAudioTapInputLayout
    private let view: UnsafeMutableAudioBufferListPointer

    init(layout: SystemAudioTapInputLayout) {
        self.layout = layout
        view = AudioBufferList.allocate(maximumBuffers: max(1, layout.tapBuffers.count))
        view.count = 0
    }

    deinit { free(view.unsafeMutablePointer) }

    /// The tap's buffers, or nil when the cycle's list no longer has the resolved shape
    /// (a reconfigured device must be rebuilt, not guessed at).
    func tapBuffers(of input: UnsafePointer<AudioBufferList>) -> UnsafePointer<AudioBufferList>? {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard source.count == layout.totalBufferCount else { return nil }
        view.count = layout.tapBuffers.count
        for (target, index) in layout.tapBuffers.enumerated() {
            view[target] = source[index]
        }
        return view.unsafePointer
    }
}
