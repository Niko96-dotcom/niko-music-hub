import AppCore
import XCTest

final class ExternalProcessRunningTests: XCTestCase {
    func testBuildsRequestWithExecutableURLAndArguments() {
        let executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let request = ExternalProcessRequest(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: ["LC_ALL": "C"]
        )

        XCTAssertEqual(request.executableURL, executableURL)
        XCTAssertEqual(request.arguments, ["--version"])
        XCTAssertEqual(request.environment, ["LC_ALL": "C"])
    }

    func testFoundationRunnerCapturesExitCodeAndOutput() async throws {
        let runner = FoundationExternalProcessRunner()
        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["Outside Cubase"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Outside Cubase")
        XCTAssertEqual(result.standardError, "")
    }

    func testFoundationRunnerCapturesLargeStandardErrorWithoutBlocking() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let runner = FoundationExternalProcessRunner()

        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: perlURL,
                arguments: ["-e", "print STDERR 'x' x 200000"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardError.count, 200000)
    }

    func testNoShellExecutionStringsAppearInRunnerSource() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Services/ExternalProcessRunning.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("\"/bin/sh\""))
        XCTAssertFalse(source.contains("\"sh\", \"-c\""))
        XCTAssertFalse(source.contains("shell"))
    }
}
