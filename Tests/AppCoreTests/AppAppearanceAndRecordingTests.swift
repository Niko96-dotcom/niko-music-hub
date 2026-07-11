import AppCore
import SwiftUI
import XCTest

final class AppAppearanceTests: XCTestCase {
    func testPreferredColorSchemeMapping() {
        XCTAssertNil(AppAppearance.followSystem.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
    }

    func testNSAppearanceNameMapping() {
        XCTAssertNil(AppAppearance.followSystem.nsAppearanceName)
        XCTAssertEqual(AppAppearance.light.nsAppearanceName, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearanceName, .darkAqua)
    }
}

final class RecordingDurationOptionsTests: XCTestCase {
    func testSupportedMinutesIncludeSettingsAndRecorderValues() {
        XCTAssertTrue(RecordingDurationOptions.supportedMinutes.contains(90))
        XCTAssertTrue(RecordingDurationOptions.supportedMinutes.contains(0))
        XCTAssertTrue(RecordingDurationOptions.supportedMinutes.contains(5))
    }

    func testNormalizedMapsUnknownValuesToNearestSupportedChoice() {
        XCTAssertEqual(RecordingDurationOptions.normalized(90), 90)
        XCTAssertEqual(RecordingDurationOptions.normalized(88), 90)
        XCTAssertEqual(RecordingDurationOptions.normalized(0), 0)
    }

    func testLabelsDistinguishUnlimited() {
        XCTAssertEqual(RecordingDurationOptions.label(for: 30), "30 minutes")
        // Chip row space is tight — unlimited renders as ∞ with the full
        // word carried by the chip's help text.
        XCTAssertEqual(RecordingDurationOptions.chipLabel(for: 0), "∞")
        XCTAssertEqual(RecordingDurationOptions.label(for: 0), "Unlimited")
    }
}

final class HelperExecutableValidationTests: XCTestCase {
    func testRejectsMissingPath() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(HelperExecutableValidation.validate(url: url), "That path does not exist.")
    }

    func testRejectsDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(HelperExecutableValidation.validate(url: directory), "Choose a file, not a folder.")
    }

    func testRejectsNonExecutableFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-validation-\(UUID().uuidString).txt")
        try "not executable".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(HelperExecutableValidation.validate(url: file), "That file is not executable.")
    }
}
