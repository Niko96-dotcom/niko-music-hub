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

    private enum CodingKeys: String, CodingKey {
        case sampleRate
        case bitDepth
        case channelCount
        case channelMode
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 44100
        let bitDepth = try container.decodeIfPresent(Int.self, forKey: .bitDepth) ?? 24
        let decodedChannelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount)
        let decodedChannelMode = try? container.decodeIfPresent(AudioChannelMode.self, forKey: .channelMode)
        let channelMode = decodedChannelMode
            ?? (decodedChannelCount == 1 ? .mono : .preserveMonoStereo)
        let channelCount = decodedChannelCount
            ?? (channelMode == .mono ? 1 : 2)

        self.init(
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            channelMode: channelMode
        )
    }

    public static let cubaseDefault = AudioPreset(
        sampleRate: 44100,
        bitDepth: 24,
        channelCount: 2,
        channelMode: .preserveMonoStereo
    )
}
