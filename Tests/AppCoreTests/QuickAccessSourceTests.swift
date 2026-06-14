import XCTest

/// Structural source-check tests asserting architectural invariants the
/// Swift compiler cannot enforce for Phase 46 (ROUT-07).
final class QuickAccessSourceTests: XCTestCase {

    // MARK: - No makeView in QuickAccess sources (ROUT-07)

    func testQuickAccessSourcesDoNotCallMakeView() throws {
        let files = [
            "Sources/AppCore/QuickAccess/QuickAccessCommand.swift",
            "Sources/AppCore/QuickAccess/QuickAccessEntry.swift",
            "Sources/AppCore/QuickAccess/QuickAccessResolver.swift",
            "Sources/AppCore/QuickAccess/QuickAccessRouter.swift",
        ]
        guard FileManager.default.fileExists(atPath: files[0]) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        for path in files {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                source.contains("makeView"),
                "QuickAccess source must not call makeView — ROUT-07: \(path)"
            )
        }
    }

    // MARK: - No OutputHandoff reference in router (HAND-04)

    func testQuickAccessRouterDoesNotReferenceOutputHandoff() throws {
        let path = "Sources/AppCore/QuickAccess/QuickAccessRouter.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(
            source.contains("OutputHandoff"),
            "QuickAccessRouter must not reference OutputHandoff — HAND-04 boundary"
        )
    }

    // MARK: - No @Observable macro in QuickAccess sources (project convention)

    func testQuickAccessSourcesDoNotUseObservableMacro() throws {
        let files = [
            "Sources/AppCore/QuickAccess/QuickAccessRouter.swift",
        ]
        guard FileManager.default.fileExists(atPath: files[0]) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        for path in files {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                source.contains("@Observable"),
                "Project convention: use ObservableObject, not @Observable macro: \(path)"
            )
        }
    }
}
