import AVFoundation
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

    func testDemoFilenameIsDetectedAsMainMix() {
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Hey Summer demo.wav"),
            .mainMix
        )
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Garden of Eden demmo.mp3"),
            .mainMix
        )
    }

    func testProductionMaturityFilenameIsDetectedAsMainMix() {
        [
            "Garden of Eden seshy.wav",
            "Garden of Eden sesh bounce.wav",
            "Garden of Eden sketch.wav",
            "Garden of Eden prod.wav",
            "Garden of Eden mix.wav",
        ].forEach { fileName in
            XCTAssertEqual(
                PreviewCandidateDetector.detectedRole(from: fileName),
                .mainMix,
                fileName
            )
        }
    }

    func testVocalStemLabelsAreDetectedWithoutMatchingUnrelatedWords() {
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "drinking kinda situation demo v1 (day one 4) (Cover) (Vocals).wav"),
            .acapella
        )
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Song a cappella.wav"),
            .acapella
        )
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Vocaloid demo.wav"),
            .mainMix
        )
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Song cover demo.wav"),
            .mainMix
        )
    }

    func testTaggedInstrumentAndEffectsExportsAreDetectedWithoutDemotingSongTitles() {
        [
            "Song demo (Cover) (Bass).wav",
            "Song demo (Cover) (FX).wav",
            "Song demo (Cover) (Synth).wav",
            "Song demo (Cover) (Guitar).wav",
            "Song demo (Cover) (Piano).wav",
        ].forEach { fileName in
            XCTAssertEqual(
                PreviewCandidateDetector.detectedRole(from: fileName),
                .stems,
                fileName
            )
        }

        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Turn Up The Bass master.wav"),
            .master,
            "An untagged word in a real song title is not an isolated-instrument export."
        )
        XCTAssertEqual(
            PreviewCandidateDetector.detectedRole(from: "Song cover demo.wav"),
            .mainMix,
            "A full-song cover without a component tag stays eligible as the preview."
        )
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

    func testRejectsPreviewFilesThatEscapeSongFolderViaSymlink() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(
            "preview-escape-\(UUID().uuidString)",
            isDirectory: true
        )
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        let mixdown = songFolder.appendingPathComponent("Mixdown", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try fm.createDirectory(at: mixdown, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let outsideWAV = outside.appendingPathComponent("escape.wav")
        let wavHeader = Self.wavHeader(sampleRate: 44_100, channels: 1, bitsPerSample: 16, durationSeconds: 1)
        fm.createFile(atPath: outsideWAV.path, contents: wavHeader)

        let link = mixdown.appendingPathComponent("escape.wav")
        try fm.createSymbolicLink(at: link, withDestinationURL: outsideWAV)

        let localWAV = mixdown.appendingPathComponent("legit.wav")
        fm.createFile(atPath: localWAV.path, contents: wavHeader)

        let candidates = try PreviewCandidateDetector(fileManager: fm).detectCandidates(in: songFolder)
        XCTAssertEqual(candidates.map(\.fileName), ["legit.wav"])
        XCTAssertFalse(candidates.contains(where: { $0.fileName == "escape.wav" }))
    }

    /// After the detector's verified open, the pathname is swapped for a link to an outside
    /// file. The duration must come from the verified descriptor (or be refused), never from
    /// the swapped-in outside file. Against the pre-fix reader, which reopens the pathname
    /// for non-WAV formats, this returns the outside duration and fails.
    func testNonWAVDurationIgnoresPathnameSwappedAfterOpen() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preview-race-\(UUID().uuidString)",
            isDirectory: true
        )
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        let mixdown = songFolder.appendingPathComponent("Mixdown", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdown, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let insideURL = mixdown.appendingPathComponent("take.m4a")
        try Self.makeM4ATone(at: insideURL, durationSeconds: 1)
        let outsideURL = outside.appendingPathComponent("evil.m4a")
        try Self.makeM4ATone(at: outsideURL, durationSeconds: 7)

        let insideDuration = try XCTUnwrap(PreviewWAVDurationReader.durationSeconds(for: insideURL))
        let outsideDuration = try XCTUnwrap(PreviewWAVDurationReader.durationSeconds(for: outsideURL))
        XCTAssertNotEqual(insideDuration, outsideDuration, accuracy: 0.5, "fixtures must be distinguishable")

        let detector = PreviewCandidateDetector(
            shouldReadDuration: { _ in true },
            durationReader: { url, descriptor in
                // The attacker wins the race between the verified open and the duration read:
                // the pathname now points outside the song folder.
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: outsideURL)
                return PreviewWAVDurationReader.durationSeconds(for: url, openedAs: descriptor)
            }
        )

        let match = try XCTUnwrap(try detector.match(
            insideURL,
            in: songFolder,
            resolve: {
                .init(
                    isContained: true,
                    canonicalPath: insideURL.path,
                    noFollowPath: NoFollowPath(base: songFolder.path, components: ["Mixdown", "take.m4a"])
                )
            }
        ))
        let candidate = detector.candidate(from: match, in: songFolder)
        XCTAssertNotNil(candidate, "a swapped pathname must not drop the candidate listing")
        // The duration is read from the verified descriptor, so it is the inside file's even
        // after the swap. A nil here would mean non-WAV durations vanished from ordinary scans.
        let duration = try XCTUnwrap(candidate?.durationSeconds, "the verified file's duration must still be read")
        XCTAssertNotEqual(
            duration,
            outsideDuration,
            accuracy: 0.5,
            "duration must not come from the file swapped in after the verified open"
        )
        XCTAssertEqual(duration, insideDuration, accuracy: 0.5, "duration must come from the verified file")
    }

    private static func makeM4ATone(at url: URL, durationSeconds: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try writeTone(into: file, durationSeconds: durationSeconds)
    }

    private static func writeTone(into file: AVAudioFile, durationSeconds: Double) throws {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate * durationSeconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(2.0 * .pi * 440.0 * Double(index) / sampleRate)) * 0.25
        }
        try file.write(from: buffer)
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
