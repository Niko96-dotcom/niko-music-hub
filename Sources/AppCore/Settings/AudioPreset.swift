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
        // S1 fail-closed: a missing key decodes to its historical default or
        // channelCount-to-mode migration, but a present value decodes strictly
        // so explicit null or malformed input throws instead of silently
        // defaulting. `contains` distinguishes missing from explicit null;
        // `decode` (not `decodeIfPresent`/`try?`) makes a present null or
        // bogus enum throw so AppSettings cannot load a silently-defaulted
        // preset and persist it over stored values via updateSettings.
        let sampleRate: Int
        if container.contains(.sampleRate) {
            sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        } else {
            sampleRate = 44100
        }
        let bitDepth: Int
        if container.contains(.bitDepth) {
            bitDepth = try container.decode(Int.self, forKey: .bitDepth)
        } else {
            bitDepth = 24
        }
        let decodedChannelCount: Int?
        if container.contains(.channelCount) {
            decodedChannelCount = try container.decode(Int.self, forKey: .channelCount)
        } else {
            decodedChannelCount = nil
        }
        let decodedChannelMode: AudioChannelMode?
        if container.contains(.channelMode) {
            decodedChannelMode = try container.decode(AudioChannelMode.self, forKey: .channelMode)
        } else {
            decodedChannelMode = nil
        }
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
