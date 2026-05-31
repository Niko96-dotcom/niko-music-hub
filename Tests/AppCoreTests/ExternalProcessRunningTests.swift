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
                arguments: ["Outside Cubase"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Outside Cubase")
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

    func testFoundationRunnerStreamsOutputBeforeCompletion() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let runner = FoundationExternalProcessRunner()
        let streamed = LockedStringArray()

        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: perlURL,
                arguments: ["-e", "$|=1; print \"first\\n\"; select undef, undef, undef, 0.05; print STDERR \"warn\\n\"; print \"second\\n\";"]
            ),
            onStandardOutput: { chunk in
                streamed.append(chunk)
            },
            onStandardError: { chunk in
                streamed.append(chunk)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(streamed.joined().contains("first"))
        XCTAssertTrue(streamed.joined().contains("warn"))
        XCTAssertTrue(result.standardOutput.contains("second"))
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

private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock {
            values.append(value)
        }
    }

    func joined() -> String {
        lock.withLock {
            values.joined()
        }
    }
}
