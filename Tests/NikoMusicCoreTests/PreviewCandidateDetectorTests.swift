import XCTest
@testable import NikoMusicCore

final class PreviewCandidateDetectorTests: XCTestCase {
    func testDetectsSupportedAudioExtensions() throws {
        try CubaseFixtures.ensureGenerated()
        let detector = PreviewCandidateDetector()
        let neonFolder = CubaseFixtures.archiveRoot.appendingPathComponent("Neon Hook", isDirectory: true)
        let candidates = try detector.detectCandidates(in: neonFolder)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.fileName.hasSuffix(".wav") })
    }

    func testSkipsWAVDurationReadsForCloudStoragePaths() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubPreview-\(UUID().uuidString)", isDirectory: true)
        let localFolder = root.appendingPathComponent("Local Song/Mixdown", isDirectory: true)
        let cloudFolder = root.appendingPathComponent("Library/CloudStorage/Dropbox/Cloud Song/Mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let localWAV = localFolder.appendingPathComponent("Local mix.wav")
        let cloudWAV = cloudFolder.appendingPathComponent("Cloud mix.wav")
        let wavHeader = Self.wavHeader(sampleRate: 44_100, channels: 1, bitsPerSample: 16, durationSeconds: 1)
        FileManager.default.createFile(atPath: localWAV.path, contents: wavHeader)
        FileManager.default.createFile(atPath: cloudWAV.path, contents: wavHeader)

        let detector = PreviewCandidateDetector()
        let localCandidates = try detector.detectCandidates(in: localFolder.deletingLastPathComponent())
        let cloudCandidates = try detector.detectCandidates(in: cloudFolder.deletingLastPathComponent())

        XCTAssertEqual(localCandidates.first?.durationSeconds, 1)
        XCTAssertNil(cloudCandidates.first?.durationSeconds)
    }

    private static func wavHeader(
        sampleRate: UInt32,
        channels: UInt16,
        bitsPerSample: UInt16,
        durationSeconds: UInt32
    ) -> Data {
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = sampleRate * UInt32(channels) * bytesPerSample * durationSeconds
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendUInt32(36 + dataSize, to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(channels, to: &data)
        appendUInt32(sampleRate, to: &data)
        appendUInt32(sampleRate * UInt32(channels) * bytesPerSample, to: &data)
        appendUInt16(channels * UInt16(bytesPerSample), to: &data)
        appendUInt16(bitsPerSample, to: &data)
        appendASCII("data", to: &data)
        appendUInt32(dataSize, to: &data)
        return data
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
