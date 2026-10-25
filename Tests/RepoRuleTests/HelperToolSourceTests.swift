import Foundation
import XCTest

/// Helpers are injected: the composition builds the probe and the locator, the locator reads no
/// process environment, and the probe runs helpers without a shell.
final class HelperToolSourceTests: XCTestCase {
    /// The two Tools switches are read only by the runtime, and every helper
    /// consumer gets its locator from `HelperToolHealth`.
    func testTheLocatorReadsNoProcessEnvironment() throws {
        let locator = SourceLex.stripped(try SourceTestSupport.read("Sources/AppCore/HelperTools/HelperToolLocator.swift"))
        XCTAssertFalse(locator.contains("ProcessInfo"))
        XCTAssertFalse(locator.contains("NIKO_MUSIC_HUB_"))
    }

    /// Every tool and the shell get the probe and locator from
    /// `ToolContext.helperHealth`; only the composition builds them.
    func testOnlyTheCompositionBuildsAProbeOrALocator() throws {
        let root = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
            guard relative.hasPrefix("Sources/Feature") || relative.hasPrefix("Sources/NikoMusicHub/") else { continue }
            guard relative != "Sources/NikoMusicHub/AppComposition.swift" else { continue }
            let code = SourceLex.stripped(try String(contentsOf: url, encoding: .utf8))
            if code.contains("HelperToolProbe(") || code.contains("HelperToolLocator(") {
                offenders.append(relative)
            }
        }
        XCTAssertEqual(offenders, [], "build them in AppComposition and read ToolContext.helperHealth")
    }

    func testTheProbeRunsHelpersWithoutAShell() throws {
        let source = try SourceTestSupport.read("Sources/AppCore/HelperTools/HelperToolProbe.swift")
        let code = SourceLex.stripped(source)
        XCTAssertFalse(code.contains("/bin/sh"))
        XCTAssertFalse(code.contains("\"-c\""))
    }
}
