import Foundation

public enum AudioChannelMode: String, Codable, Sendable, CaseIterable {
    case preserveMonoStereo
    case mono
    case stereo
}

public struct AudioPreset: Equatable, Codable, Sendable {
    public var sampleRate: Int
    public var bitDepth: Int
    public var channelCount: Int
    public var channelMode: AudioChannelMode

    public init(
        sampleRate: Int = 44100,
        bitDepth: Int = 24,
        channelCount: Int = 2,
        channelMode: AudioChannelMode = .preserveMonoStereo
    ) {
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.channelMode = channelMode
    }

    public static let cubaseDefault = AudioPreset(
        sampleRate: 44100,
        bitDepth: 24,
        channelCount: 2,
        channelMode: .preserveMonoStereo
    )
}
