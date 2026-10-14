import Foundation
import XCTest

/// Archive previews are output-only. When the default output device also has input streams
/// (a duplex interface or a virtual device such as "Jump Desktop Audio"), macOS coreaudiod
/// still asks TCC for microphone access as soon as any client starts IO on that device, and it
/// holds the IO start until the prompt is answered. That gate is outside the app; this guard
/// keeps the preview path from adding a real input dependency on top of it.
final class ArchivePreviewOutputOnlySourceTests: XCTestCase {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

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
        "AudioCaptureActivity.shared.setActive",
    ]

    func testPreviewPlaybackSourcesNeverTouchAudioInput() throws {
        var hits: [String] = []
        for directory in ["Sources/FeatureArchiveBrowser", "Sources/NikoMusicCore/Preview"] {
            for file in try swiftFiles(in: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for api in Self.inputAPIHits(in: source) {
                    hits.append("\(directory)/\(file.lastPathComponent): \(api)")
                }
            }
        }
        XCTAssertEqual(hits, [], "Preview playback must stay output-only (AVPlayer); move capture work to FeatureAudioRecorder")
    }

    func testPreviewPlaybackStaysOnAVPlayer() throws {
        let player = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Sources/FeatureArchiveBrowser/ArchivePreviewPlayer.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(player.contains("AVPlayer(playerItem: item)"))
    }

    func testMatcherFindsInputAPIsAndIgnoresComments() {
        let sample = """
        // inputNode in a comment is fine
        let engine = AVAudioEngine()
        _ = engine.inputNode
        """
        XCTAssertEqual(Self.inputAPIHits(in: sample), ["inputNode", "AVAudioEngine("])
    }

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

    private func swiftFiles(in relativeDirectory: String) throws -> [URL] {
        let directory = Self.packageRoot.appendingPathComponent(relativeDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "No Swift sources found in \(relativeDirectory)")
        return files
    }
}
