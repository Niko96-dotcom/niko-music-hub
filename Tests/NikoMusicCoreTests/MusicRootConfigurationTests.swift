import Foundation
import XCTest
@testable import NikoMusicCore

final class MusicRootConfigurationTests: XCTestCase {
    func testStoredRootRoundTripsBookmarkAndResolvesIt() throws {
        let expected = URL(fileURLWithPath: "/tmp/resolved-vault-root", isDirectory: true)
        let root = StoredMusicRoot(
            id: UUID(), role: .archive, displayName: "Archive", pathFallback: "/old/path",
            securityScopedBookmark: Data("bookmark".utf8), isEnabled: true
        )
        let decoded = try JSONDecoder().decode(StoredMusicRoot.self, from: JSONEncoder().encode(root))
        XCTAssertEqual(decoded, root)
        XCTAssertEqual(try decoded.resolvedURL(using: StubBookmarkResolver(url: expected)), expected)
    }

    func testValidatorRejectsEqualNestedAndSymlinkOverlaps() throws {
        let base = try makeDirectory("validation")
        defer { try? FileManager.default.removeItem(at: base) }
        let active = try makeDirectory("active", under: base)
        let nested = try makeDirectory("nested", under: active)
        let archive = try makeDirectory("archive", under: base)
        let link = base.appendingPathComponent("archive-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: active)
        let validator = MusicRootValidator(applicationDataRoots: [])

        XCTAssertThrowsError(try validator.validate(activeRoot: active, archiveRoot: active))
        XCTAssertThrowsError(try validator.validate(activeRoot: active, archiveRoot: nested))
        XCTAssertThrowsError(try validator.validate(activeRoot: active, archiveRoot: link))
        XCTAssertNoThrow(try validator.validate(activeRoot: active, archiveRoot: archive))
    }

    func testValidatorRejectsApplicationDataOverlap() throws {
        let base = try makeDirectory("app-data")
        defer { try? FileManager.default.removeItem(at: base) }
        let appData = try makeDirectory("Niko Music Hub", under: base)
        let inside = try makeDirectory("Vault", under: appData)
        let outside = try makeDirectory("Outside", under: base)
        let validator = MusicRootValidator(applicationDataRoots: [appData])

        XCTAssertThrowsError(try validator.validate(activeRoot: inside, archiveRoot: outside)) { error in
            guard case MusicRootValidationError.rootOverlapsApplicationData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeDirectory(_ name: String, under parent: URL? = nil) throws -> URL {
        let url = (parent ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubBookmarkResolver: SecurityScopedBookmarkResolving {
    let url: URL
    func resolveBookmark(_ data: Data) throws -> URL { url }
}
