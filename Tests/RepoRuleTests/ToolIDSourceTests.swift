import AppCore
import Foundation
import XCTest

/// Each built-in tool ID is defined once, in `BuiltInToolIDs.swift`; every other
/// file uses the constant. Before, "wav-converter" and "archive-browser" were spelled
/// in eleven files each, and nothing checked that they agreed.
final class ToolIDSourceTests: XCTestCase {
    static let ownerPath = "Sources/AppCore/Features/BuiltInToolIDs.swift"

    func testBuiltInToolIDsAreSpelledOnlyInTheirCatalog() throws {
        let ids: [ToolFeatureID] = [
            .archiveBrowser, .bpmTapper, .wavConverter, .audioRecorder, .downloader, .stemSeparation,
        ]
        var failures: [String] = []
        for file in try Self.swiftFiles() where file != Self.ownerPath {
            let source = SourceLex.strippedCommentsOnly(try SourceTestSupport.read(file))
            for id in ids where source.contains("\"\(id.rawValue)\"") {
                failures.append("\(file): \"\(id.rawValue)\"")
            }
        }
        XCTAssertEqual(
            failures,
            [],
            "Use the ToolFeatureID constant from \(Self.ownerPath) instead of the literal:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// Settings is known by its section (`ToolSection.settings`), not by its ID: the
    /// ID is spelled only where the Settings tool declares it.
    func testSettingsToolIDIsSpelledOnlyInItsFeature() throws {
        let owner = "Sources/NikoMusicHub/Settings/SettingsFeature.swift"
        var failures: [String] = []
        for file in try Self.swiftFiles() where file != owner {
            if SourceLex.strippedCommentsOnly(try SourceTestSupport.read(file)).contains("\"settings\"") {
                failures.append(file)
            }
        }
        XCTAssertEqual(failures, [], "Check `metadata.section == .settings` instead of the Settings ID")
        XCTAssertTrue(try SourceTestSupport.read(owner).contains("section: .settings"))
    }

    /// The IDs are stored and typed (`-ui-tool`, the shell's selection, inbox items).
    func testBuiltInToolIDsKeepTheirStoredStrings() {
        XCTAssertEqual(
            [ToolFeatureID.archiveBrowser, .bpmTapper, .wavConverter, .audioRecorder, .downloader, .stemSeparation]
                .map(\.rawValue),
            ["archive-browser", "bpm-tapper", "wav-converter", "audio-recorder", "downloader", "stem-separation"]
        )
    }

    private static func swiftFiles() throws -> [String] {
        let root = SourceTestSupport.packageRoot
        let sources = root.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)) }
            .sorted()
        XCTAssertGreaterThan(files.count, 100, "Sources/ walk found too few files")
        return files
    }
}
