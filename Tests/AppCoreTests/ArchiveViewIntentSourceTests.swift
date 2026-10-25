import Foundation
import XCTest

/// Archive views state intent; `ArchivePageModel` owns the page. Views that wrote
/// `viewMode` themselves drifted from the model's own rules before (477f9ae fixed
/// four view copies of `showsBoardPage`). The setters are `private(set)` in
/// `ArchivePageModel`, so the compiler refuses a write elsewhere; this test keeps
/// that file the one writer if the setters ever open up.
final class ArchiveViewIntentSourceTests: XCTestCase {
    func testOnlyThePageModelWritesThePage() throws {
        let failures = try Self.archiveSourceFiles()
            .filter { !Self.isPageOwnerFile($0) }
            .flatMap { file in
                Self.lines(matching: Self.pageWrite, in: SourceLex.stripped(try SourceTestSupport.read(file)))
                    .map { "\(file):\($0)" }
            }
        XCTAssertEqual(
            failures,
            [],
            "Views call an intent (openSongDetail, showBoard, setBrowseLayout(list:), showAnalytics, "
                + "clearSelection, …) instead of writing viewMode or listShowsDetail:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// The detector must catch a view write and leave reads and declarations alone.
    func testPageWriteDetector() {
        func hits(_ line: String) -> Int {
            Self.lines(matching: Self.pageWrite, in: SourceLex.stripped(line)).count
        }
        XCTAssertEqual(hits("viewModel.page.viewMode = .board"), 1)
        XCTAssertEqual(hits("viewModel.page.listShowsDetail = false"), 1)
        XCTAssertEqual(hits("onOpenListView: { viewModel.page.viewMode = .list }"), 1)
        XCTAssertEqual(hits("if viewModel.page.viewMode == .board {"), 0)
        XCTAssertEqual(hits("guard viewMode != .list else { return }"), 0)
        XCTAssertEqual(hits("@Published private(set) var viewMode: ArchiveViewMode = .board {"), 0)
        XCTAssertEqual(hits("Self.navigationRoute(viewMode: viewMode, songID: nil)"), 0)
        XCTAssertEqual(hits("// viewModel.page.viewMode = .board"), 0)
    }

    /// The song detail's status menu offers a change only when the board and the
    /// metadata coordinator would accept it: `canMutateWorkflowStatus`, not the
    /// shorter file-action block (which stays off during an archive transfer).
    func testSongDetailStatusMenuUsesTheStatusGate() throws {
        let source = SourceLex.stripped(try SourceTestSupport.read("Sources/FeatureArchiveBrowser/SongDetailView.swift"))
        let menu = try XCTUnwrap(source.range(of: "ArchiveWorkflowStatusMenu("), "the detail has a status menu")
        let disabled = try XCTUnwrap(source.range(of: ".disabled(", range: menu.upperBound..<source.endIndex))
        let argument = Self.parenthesized(source, from: disabled.upperBound)
        XCTAssertTrue(argument.contains("canMutateWorkflowStatus"), "status menu gate: \(argument)")
        XCTAssertFalse(argument.contains("blocksGenericProjectVaultFileActions"), "status menu gate: \(argument)")
    }

    // MARK: - Detectors

    /// The text up to the parenthesis that closes the one opened just before `start`.
    private static func parenthesized(_ source: String, from start: String.Index) -> String {
        var depth = 1
        var index = start
        while index < source.endIndex {
            switch source[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return String(source[start..<index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return String(source[start...])
    }

    private static let pageWrite = try! NSRegularExpression(pattern: #"\b(?:viewMode|listShowsDetail)\s*=(?!=)"#)

    private static func isPageOwnerFile(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == "ArchivePageModel.swift"
    }

    private static func lines(matching pattern: NSRegularExpression, in strippedSource: String) -> [String] {
        let ns = strippedSource as NSString
        return pattern.matches(in: strippedSource, range: NSRange(location: 0, length: ns.length)).map { match in
            let line = ns.substring(to: match.range.location).components(separatedBy: "\n").count
            return "\(line): \(ns.substring(with: match.range))"
        }
    }

    private static func archiveSourceFiles() throws -> [String] {
        let root = SourceTestSupport.packageRoot.standardizedFileURL.path
        let directory = SourceTestSupport.packageRoot.appendingPathComponent("Sources/FeatureArchiveBrowser")
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(root.count + 1)) }
            .sorted()
        XCTAssertGreaterThan(files.count, 50, "Sources/FeatureArchiveBrowser walk found too few files")
        return files
    }
}
