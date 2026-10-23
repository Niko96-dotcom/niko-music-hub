import Foundation
import XCTest

/// Archive views state intent; the view model owns the page. Views that wrote
/// `viewMode` themselves drifted from the model's own rules before (477f9ae fixed
/// four view copies of `showsBoardPage`).
final class ArchiveViewIntentSourceTests: XCTestCase {
    func testOnlyTheViewModelWritesThePage() throws {
        let failures = try Self.archiveSourceFiles()
            .filter { !Self.isViewModelFile($0) }
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
        XCTAssertEqual(hits("viewModel.viewMode = .board"), 1)
        XCTAssertEqual(hits("viewModel.listShowsDetail = false"), 1)
        XCTAssertEqual(hits("onOpenListView: { viewModel.viewMode = .list }"), 1)
        XCTAssertEqual(hits("if viewModel.viewMode == .board {"), 0)
        XCTAssertEqual(hits("guard viewMode != .list else { return }"), 0)
        XCTAssertEqual(hits("@Published var viewMode: ArchiveViewMode = .board {"), 0)
        XCTAssertEqual(hits("Self.navigationRoute(viewMode: viewMode, songID: nil)"), 0)
        XCTAssertEqual(hits("// viewModel.viewMode = .board"), 0)
    }

    // MARK: - Detectors

    private static let pageWrite = try! NSRegularExpression(pattern: #"\b(?:viewMode|listShowsDetail)\s*=(?!=)"#)

    private static func isViewModelFile(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.hasPrefix("ArchiveBrowserViewModel")
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
