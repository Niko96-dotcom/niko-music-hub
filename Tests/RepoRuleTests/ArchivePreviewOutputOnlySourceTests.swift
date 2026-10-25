import XCTest

/// Archive previews are output-only. When the default output device also has input streams (a duplex
/// interface or a virtual device such as "Jump Desktop Audio"), macOS coreaudiod still asks TCC for
/// microphone access as soon as any client starts IO on that device, and it holds the IO start until
/// the prompt is answered. That gate is outside the app; this guard keeps the preview path from adding
/// a real input dependency on top of it.
/// AGENTS.md row "Preview is output-only"; docs/architecture.md § Archive preview playback.
final class ArchivePreviewOutputOnlySourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Preview is output-only",
        why: "An input API on the preview path asks for the microphone and can hold playback until the prompt is answered",
        see: "AGENTS.md row \"Preview is output-only\"; docs/architecture.md § Archive preview playback",
        fix: "Keep previews on AVPlayer; move capture work to FeatureAudioRecorder"
    )

    /// Audio-input, capture and tap APIs. None of them belongs on the preview path.
    private static let inputAPIs = [
        "inputNode",
        "AVAudioEngine(",
        "AVAudioRecorder",
        "AVCaptureDevice",
        "AVCaptureSession",
        "AVAudioApplication",
        "requestRecordPermission",
        "AudioQueueNewInput",
        "kAudioOutputUnitProperty_EnableIO",
        "kAudioHardwarePropertyDefaultInputDevice",
        "kAudioHardwarePropertyProcessInputMute",
        "kAudioObjectPropertyScopeInput",
        "kAudioDevicePropertyScopeInput",
        "AudioDeviceCreateIOProcID",
        "AudioHardwareCreateAggregateDevice",
        "AudioHardwareCreateProcessTap",
        "CATapDescription",
        "ScreenCaptureKit",
        "SCStream",
        // The recorder alone sets the recording signal; preview only observes it.
        "setActive(",
    ]

    /// The top-level files of the archive feature and of Core's Preview folder.
    func testPreviewPlaybackSourcesNeverTouchAudioInput() {
        let files = ["Sources/FeatureArchiveBrowser/", "Sources/NikoMusicCore/Preview/"].flatMap { folder in
            SourceTree.swiftFiles(under: folder).filter { !$0.dropFirst(folder.count).contains("/") }
        }
        Self.rule.check(files.flatMap { file in Self.inputAPIHits(in: SourceTree.read(file)).map { "\(file) uses `\($0)`" } })
    }

    func testPreviewPlaybackStaysOnAVPlayer() {
        Self.rule.expect("Sources/FeatureArchiveBrowser/ArchivePreviewPlayer.swift", contains: ["AVPlayer(playerItem: item)"])
    }

    func testMatcherFindsInputAPIsAndIgnoresComments() {
        let sample = """
        // inputNode in a comment is fine
        let engine = AVAudioEngine()
        _ = engine.inputNode
        """
        XCTAssertEqual(Self.inputAPIHits(in: sample), ["inputNode", "AVAudioEngine("])
    }

    /// Line comments are dropped; string literals stay (a selector or a key path can name an API).
    private static func inputAPIHits(in source: String) -> [String] {
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[..<comment.lowerBound]
            }
            .joined(separator: "\n")
        return inputAPIs.filter { code.contains($0) }
    }
}
