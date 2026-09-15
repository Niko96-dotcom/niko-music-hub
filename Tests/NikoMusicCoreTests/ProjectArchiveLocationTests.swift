import Foundation
@testable import NikoMusicCore
import XCTest

final class ProjectArchiveLocationTests: XCTestCase {
    func testAvailabilityInspectsFilesInsideLocallyPresentFolders() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(try ProjectArchiveAvailabilityProbe().availability(at: folder), .local)
        let onlineAudio = ProjectArchiveAvailabilityProbe { url in
            url.lastPathComponent == "audio.wav" ? .onlineOnly : .local
        }
        XCTAssertEqual(try onlineAudio.availability(at: folder), .onlineOnly)
        let downloading = ProjectArchiveAvailabilityProbe { url in
            url.lastPathComponent == "audio.wav" ? .materializing : .onlineOnly
        }
        XCTAssertEqual(try downloading.availability(at: folder), .materializing)
        let unknown = ProjectArchiveAvailabilityProbe { _ in throw FileProviderArchiveStorageError.lookupUnavailable }
        XCTAssertThrowsError(try unknown.availability(at: folder))
        XCTAssertEqual(try onlineAudio.availability(at: folder.appendingPathComponent("Absent")), .missing)
    }

    func testResolverRejectsChangedRootTraversalAndNestedSymlinks() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootID = UUID()
        let resolver = ProjectArchiveLocationResolver(rootID: rootID, rootURL: folder)
        let valid = ProjectLocation(rootID: rootID, relativePath: "Audio", kind: .archive)
        XCTAssertNotNil(resolver.resolve(valid))
        XCTAssertNil(resolver.resolve(ProjectLocation(rootID: UUID(), relativePath: "Audio", kind: .archive)))
        for path in ["../Other", "generations/id", ".niko-staging/id"] {
            XCTAssertNil(resolver.resolve(ProjectLocation(rootID: rootID, relativePath: path, kind: .archive)))
        }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Link"), withDestinationURL: folder.appendingPathComponent("Audio"))
        XCTAssertNil(resolver.resolve(ProjectLocation(rootID: rootID, relativePath: "Link", kind: .archive)))
        XCTAssertThrowsError(try ProjectArchiveAvailabilityProbe().availability(at: folder))
    }

    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("archive-locality-\(UUID())")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Audio"), withIntermediateDirectories: true)
        try Data("project".utf8).write(to: folder.appendingPathComponent("Song.cpr"))
        try Data("audio".utf8).write(to: folder.appendingPathComponent("Audio/audio.wav"))
        return folder
    }
}
