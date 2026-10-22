import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// A tool run writes into a destination whose folder and guard come from one
/// throwing settings read.
final class ToolOutputDestinationTests: XCTestCase {
    private var tempRoot: URL!
    private var suiteName: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-output-destination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        suiteName = "tool-output-destination-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() throws -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(userDefaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    func testUnreadableSettingsThrowInsteadOfFallingBackToDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Data("not json".utf8), forKey: "nikoMusicHub.settings")
        XCTAssertThrowsError(try ToolOutputDestination.load(from: try makeStore()))
    }

    func testFirstRunWithNothingSavedLoadsTheDefaultFolder() throws {
        let destination = try ToolOutputDestination.load(from: try makeStore())
        XCTAssertEqual(destination.folder, StoredFolderLocation.defaultOutputFolder)
        XCTAssertNoThrow(try destination.validate(tempRoot), "no music roots saved, so nothing is refused")
    }

    func testValidateRefusesMusicRootsAndAdmitsTheOutputFolderAndBelow() throws {
        let musicRoot = tempRoot.appendingPathComponent("Music", isDirectory: true)
        let output = tempRoot.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: musicRoot, withIntermediateDirectories: true)
        let destination = ToolOutputDestination(settings: AppSettings(
            outputFolder: StoredFolderLocation(url: output),
            musicRoots: [StoredMusicRoot(role: .scanOnly, url: musicRoot)]
        ))

        XCTAssertEqual(destination.folder, output)
        XCTAssertNoThrow(try destination.validate(output))
        XCTAssertNoThrow(try destination.validate(output.appendingPathComponent("Run 1", isDirectory: true)))
        XCTAssertThrowsError(try destination.validate(musicRoot))
        XCTAssertThrowsError(try destination.validate(musicRoot.appendingPathComponent("Song", isDirectory: true)))
    }

    /// The folder and the guard stay bound to the snapshot they were read from,
    /// even when settings change before the run writes.
    func testADestinationStaysBoundToItsSnapshot() throws {
        let store = try makeStore()
        let firstOutput = tempRoot.appendingPathComponent("First", isDirectory: true)
        let laterRoot = tempRoot.appendingPathComponent("Later Root", isDirectory: true)
        try FileManager.default.createDirectory(at: laterRoot, withIntermediateDirectories: true)
        try store.saveSettings(AppSettings(outputFolder: StoredFolderLocation(url: firstOutput)))

        let destination = try ToolOutputDestination.load(from: store)
        try store.saveSettings(AppSettings(
            outputFolder: StoredFolderLocation(url: laterRoot),
            musicRoots: [StoredMusicRoot(role: .scanOnly, url: laterRoot)]
        ))

        XCTAssertEqual(destination.folder, firstOutput)
        XCTAssertNoThrow(try destination.validate(laterRoot), "the later root is not part of this run's snapshot")
        XCTAssertThrowsError(try ToolOutputDestination.load(from: store).validate(laterRoot))
    }
}
