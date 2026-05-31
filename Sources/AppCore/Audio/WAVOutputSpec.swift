import Foundation

public struct WAVOutputSpec: Equatable, Codable, Sendable {
    public var sampleRate: Int
    public var bitDepth: Int
    public var channelCount: Int

    public init(
        sampleRate: Int,
        bitDepth: Int,
        channelCount: Int
    ) {
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
    }

    public init(preset: AudioPreset, channelCount: Int) {
        self.init(
            sampleRate: preset.sampleRate,
            bitDepth: preset.bitDepth,
            channelCount: channelCount
        )
    }
}
