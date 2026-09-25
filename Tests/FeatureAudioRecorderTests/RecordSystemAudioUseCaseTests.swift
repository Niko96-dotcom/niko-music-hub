import AppCore
import XCTest
@testable import FeatureAudioRecorder

final class RecordSystemAudioUseCaseTests: XCTestCase {
    func testExecuteStartsRecording() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let tempDir = FileManager.default.temporaryDirectory

        let config = RecordSystemAudioUseCase.Config(
            outputURL: tempDir,
            preset: .cubaseDefault,
            maxDuration: 1.0,
            filenameOverride: nil
        )

        let result = try await useCase.execute(config: config)

        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)
    }

    func testGenerateOutputFilenameWithOverride() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: "Custom Name.wav")
        XCTAssertEqual(filename, "Custom Name.wav")
    }

    func testGenerateOutputFilenameNormalizesMP3OverrideToWAV() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.mp3"), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "my.session.take.01.MP3"), "my.session.take.01.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take"), "Take.wav")
    }

    func testGenerateOutputFilenamePreservesWAVCasing() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.WAV"), "Take.WAV")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.wav"), "Take.wav")
    }

    func testGenerateOutputFilenameStripsTrailingDotsBeforeWAVDecision() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.wav."), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.WAV..."), "Take.WAV")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.mp3."), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.mp3..."), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take."), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take..."), "Take.wav")
    }

    func testGenerateOutputFilenameTrailingDotsWhitespaceAndPlainDotsStaySafeWAV() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        XCTAssertEqual(useCase.generateOutputFilename(override: "  Take.wav.  "), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "  Take.mp3.  "), "Take.wav")
        for dotOnly in [".", "..", "...", ".....", "/"] {
            let filename = useCase.generateOutputFilename(override: dotOnly)
            XCTAssertTrue(filename.hasPrefix("Recording "), "dot-only override must use default, got: \(filename)")
            XCTAssertTrue(filename.hasSuffix(".wav"), "default must end in .wav, got: \(filename)")
        }
    }

    func testGenerateOutputFilenameWhitespaceOnlyFallsBackToDefault() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        for override in ["   ", "\t\n ", ""] {
            let filename = useCase.generateOutputFilename(override: override)
            XCTAssertTrue(filename.hasPrefix("Recording "), "whitespace override must use default, got: \(filename)")
            XCTAssertTrue(filename.hasSuffix(".wav"), "default must end in .wav, got: \(filename)")
        }
    }

    func testGenerateOutputFilenameKeepsHiddenAndMultidotNamesMeaningful() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        XCTAssertEqual(useCase.generateOutputFilename(override: ".take"), ".take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "my.session.01"), "my.session.01.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "my.session.take.mp3"), "my.session.take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "  spaced take  "), "spaced take.wav")
    }

    func testResolvedOutputURLNormalizesTraversalMP3InsideDirectory() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-safe-\(UUID().uuidString)", isDirectory: true)

        let resolved = useCase.resolvedOutputURL(config: .init(
            outputURL: outputDirectory,
            preset: .cubaseDefault,
            filenameOverride: "../Outside.mp3"
        ))

        XCTAssertEqual(resolved.deletingLastPathComponent().standardizedFileURL, outputDirectory.standardizedFileURL)
        XCTAssertEqual(resolved.lastPathComponent, "Outside.wav")
    }

    func testResolvedOutputURLResolvesCollisionWithNumericSuffix() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-collision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        try Data("existing".utf8).write(to: outputDirectory.appendingPathComponent("Take.wav"))

        let resolved = useCase.resolvedOutputURL(config: .init(
            outputURL: outputDirectory,
            preset: .cubaseDefault,
            filenameOverride: "Take.mp3"
        ))

        XCTAssertEqual(resolved.lastPathComponent, "Take (1).wav")
        XCTAssertEqual(resolved.deletingLastPathComponent().standardizedFileURL, outputDirectory.standardizedFileURL)
    }

    func testFilenameOverrideCannotEscapeOutputDirectory() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-safe-\(UUID().uuidString)", isDirectory: true)

        let resolved = useCase.resolvedOutputURL(config: .init(
            outputURL: outputDirectory,
            preset: .cubaseDefault,
            filenameOverride: "../Outside.wav"
        ))

        XCTAssertEqual(resolved.deletingLastPathComponent().standardizedFileURL, outputDirectory.standardizedFileURL)
        XCTAssertEqual(resolved.lastPathComponent, "Outside.wav")
    }

    func testEnsureOutputDirectoryCreatesMissingParent() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-ensure-dir-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("Nested", isDirectory: true)
        let fileURL = outputDirectory.appendingPathComponent("Recording.wav")
        defer { try? FileManager.default.removeItem(at: root) }

        try useCase.ensureOutputDirectoryExists(for: fileURL)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testGenerateOutputFilenameWithoutOverride() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: nil)
        XCTAssertTrue(filename.hasPrefix("Recording "))
        XCTAssertTrue(filename.hasSuffix(".wav"))
    }

    func testGenerateOutputFilenameRejectsRelativeDotSegmentsLexically() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let frozen = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5
        )))
        let expectedDefault = useCase.generateOutputFilename(override: nil, now: { frozen })
        XCTAssertEqual(expectedDefault, "Recording 2020-01-02 03-04-05.wav")
        for override in ["../..", "./.", "foo/..", "nested/...", "../", "./", "a/b/../.."] {
            XCTAssertEqual(
                useCase.generateOutputFilename(override: override, now: { frozen }),
                expectedDefault,
                "override \(override) must fall back without CWD resolution"
            )
        }
        // Positive basename contract still holds: path strings yield a basename.
        XCTAssertEqual(useCase.generateOutputFilename(override: "../Outside.mp3"), "Outside.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "a/b/c/Take.mp3"), "Take.wav")
    }

    func testGenerateOutputFilenameHandlesRootAndTrailingSlashesLexically() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let frozen = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5
        )))
        let expectedDefault = useCase.generateOutputFilename(override: nil, now: { frozen })
        for override in ["/", "///"] {
            XCTAssertEqual(
                useCase.generateOutputFilename(override: override, now: { frozen }),
                expectedDefault,
                "root \(override) must fall back"
            )
        }
        XCTAssertEqual(useCase.generateOutputFilename(override: "foo/"), "foo.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "foo///"), "foo.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.wav/"), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.wav///"), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "nested/dir/Take.mp3/"), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "a/b/c"), "c.wav")
    }

    func testGenerateOutputFilenameDotfilesLexicalExtension() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        // Dotfiles preserve a meaningful name and never derive from the CWD.
        XCTAssertEqual(useCase.generateOutputFilename(override: ".mp3"), ".mp3.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: ".WAV"), ".WAV")
        XCTAssertEqual(useCase.generateOutputFilename(override: ".hiddenname"), ".hiddenname.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: ".hidden.mp3"), ".hidden.wav")
        // Normal cases alongside the dotfile contract.
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.wav"), "Take.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "Take.WAV..."), "Take.WAV")
        XCTAssertEqual(useCase.generateOutputFilename(override: "multidot.my.session.01"), "multidot.my.session.01.wav")
        XCTAssertEqual(useCase.generateOutputFilename(override: "my.session.take.01.MP3"), "my.session.take.01.wav")
    }

    // NMH-064: preview and write share one formatter; a frozen instant
    // renders the exact next-take name.
    func testPreviewNameMatchesGenerateOutputFilenameWithFrozenNow() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let frozen = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5
        )))
        XCTAssertEqual(
            useCase.generateOutputFilename(override: nil, now: { frozen }),
            "Recording 2020-01-02 03-04-05.wav"
        )
    }
}

private final class MockAudioCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        recording = true
        return AsyncStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                continuation.finish()
            }
        }
    }

    func stopRecording() async throws -> RecorderResult {
        recording = false
        return RecorderResult(
            outputURL: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 0.1,
            sampleRate: 44100,
            bitDepth: 24,
            channelCount: 2
        )
    }
}
