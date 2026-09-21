import FeatureStemSeparation
import Foundation
import Testing

struct DemucsMLXProgressParserTests {

    private let parser = DemucsMLXProgressParser()

    @Test
    func terminalOutputBecomesReadableProgress() {
        let result = parser.parse(line: "\u{001B}[32mTracks: 50%|████ | 1/2 [00:10<00:10, 0.1track/s]")
        #expect(result?.progress == 0.5)
        #expect(result?.message == "Separating stems…")
        #expect(parser.parse(line: "Model htdemucs_6s version 4.0") == nil)
        #expect(parser.parse(line: "/tmp/song2026.wav") == nil)
        #expect(parser.parse(line: "WARNING: backend initialized") == nil)
    }

    @Test
    func parse_progressLines() {
        let cases: [(String, Double?)] = [
            ("0%", 0.0),
            ("50%", 0.5),
            ("100%", 1.0),
            ("progress: 0.75", 0.75),
            ("separating", nil),
            ("Loading model htdemucs", nil),
            ("", nil)
        ]
        for (line, expected) in cases {
            let result = parser.parse(line: line)
            if let expected {
                #expect(result?.progress == expected, "For '\(line)'")
            } else {
                #expect(result?.progress == nil, "For '\(line)'")
            }
        }
    }

    @Test
    func parse_successFixture() throws {
        let url = try fixtureURL(named: "demucs-mlx-success")
        let lines = try String(contentsOf: url).components(separatedBy: .newlines)
        var progressValues: [Double] = []
        var messages: [String] = []
        for line in lines {
            if let parsed = parser.parse(line: line) {
                if let progress = parsed.progress {
                    progressValues.append(progress)
                }
                if let message = parsed.message {
                    messages.append(message)
                }
            }
        }
        #expect(progressValues.contains(0.0))
        #expect(progressValues.contains(0.5))
        #expect(progressValues.contains(1.0))
        #expect(messages.contains("Loading model…"))
    }

    @Test
    func parse_modelErrorFixture_capturesDownloadProgress() throws {
        let url = try fixtureURL(named: "demucs-mlx-model-error")
        let lines = try String(contentsOf: url).components(separatedBy: .newlines)
        var progressValues: [Double] = []
        var messages: [String] = []
        for line in lines {
            if let parsed = parser.parse(line: line) {
                if let progress = parsed.progress {
                    progressValues.append(progress)
                }
                if let message = parsed.message {
                    messages.append(message)
                }
            }
        }
        #expect(messages.contains("Downloading model…"))
        #expect(progressValues.contains(0.25))
        #expect(progressValues.contains(0.5))
    }
}

private func fixtureURL(named name: String) throws -> URL {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: "log") else {
        throw TestError("Fixture \(name).log not found in bundle")
    }
    return url
}

private struct TestError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
