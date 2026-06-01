import AppCore
import XCTest

final class ExternalProcessRunningTests: XCTestCase {
    func testBuildsRequestWithExecutableURLAndArguments() {
        let executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let request = ExternalProcessRequest(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: ["LC_ALL": "C"],
            timeoutSeconds: 5
        )

        XCTAssertEqual(request.executableURL, executableURL)
        XCTAssertEqual(request.arguments, ["--version"])
        XCTAssertEqual(request.environment, ["LC_ALL": "C"])
        XCTAssertEqual(request.timeoutSeconds, 5)
    }

    func testFoundationRunnerCapturesExitCodeAndOutput() async throws {
        let runner = FoundationExternalProcessRunner()
        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["Niko Music Hub"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Niko Music Hub")
        XCTAssertEqual(result.standardError, "")
    }

    func testFoundationRunnerTimesOutAndTerminatesProcess() async throws {
        let runner = FoundationExternalProcessRunner()

        do {
            _ = try await runner.run(
                ExternalProcessRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["5"],
                    timeoutSeconds: 0.2
                )
            )
            XCTFail("Expected timeout")
        } catch let error as ExternalProcessError {
            XCTAssertEqual(error, .timedOut(executable: "sleep", seconds: 0.2))
        }
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
