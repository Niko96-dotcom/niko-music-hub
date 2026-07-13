import AppCore
import Darwin
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

    func testTimeoutReturnsPromptlyWhenChildIgnoresSIGTERM() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let runner = FoundationExternalProcessRunner(terminationGraceSeconds: 0.05)
        let startedAt = ContinuousClock.now

        do {
            _ = try await runner.run(
                ExternalProcessRequest(
                    executableURL: perlURL,
                    arguments: ["-e", "$SIG{TERM}='IGNORE'; sleep 10"],
                    timeoutSeconds: 0.1
                )
            )
            XCTFail("Expected timeout")
        } catch let error as ExternalProcessError {
            XCTAssertEqual(error, .timedOut(executable: "perl", seconds: 0.1))
        }

        XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    }

    func testTimeoutKillsDescendantProcessGroup() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-descendant-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let runner = FoundationExternalProcessRunner(terminationGraceSeconds: 0.05)
        let script = """
        $child=fork();
        if ($child == 0) {
          $SIG{TERM}='IGNORE';
          open($fh, '>', $ARGV[0]) or die $!;
          print $fh $$;
          close($fh);
          sleep 10;
          exit 0;
        }
        $SIG{TERM}='IGNORE';
        sleep 10;
        """

        do {
            _ = try await runner.run(
                ExternalProcessRequest(
                    executableURL: perlURL,
                    arguments: ["-e", script, pidFile.path],
                    timeoutSeconds: 0.3
                )
            )
            XCTFail("Expected timeout")
        } catch let error as ExternalProcessError {
            XCTAssertEqual(error, .timedOut(executable: "perl", seconds: 0.3))
        }

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let descendantPID = try XCTUnwrap(pid_t(pidText))
        for _ in 0..<100 where kill(descendantPID, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(descendantPID, 0), -1, "Descendant process survived group termination")
        XCTAssertEqual(errno, ESRCH)
    }

    func testCapturedOutputUsesBoundedRingBuffer() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let limit = 32 * 1024
        let runner = FoundationExternalProcessRunner(maximumCapturedOutputBytes: limit)

        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: perlURL,
                arguments: ["-e", "print 'a' x (2 * 1024 * 1024)"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.utf8.count, limit)
        XCTAssertTrue(result.standardOutputWasTruncated)
    }

    func testTaskCancellationReturnsWithoutWaitingForIgnoredTERMChild() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let runner = FoundationExternalProcessRunner(terminationGraceSeconds: 0.05)
        let task = Task {
            try await runner.run(
                ExternalProcessRequest(
                    executableURL: perlURL,
                    arguments: ["-e", "$SIG{TERM}='IGNORE'; sleep 10"]
                )
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        let canceledAt = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertLessThan(canceledAt.duration(to: .now), .seconds(1))
    }

    func testSignalTerminationIsTyped() async throws {
        let shellURL = URL(fileURLWithPath: "/bin/sh")
        let runner = FoundationExternalProcessRunner()

        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: shellURL,
                arguments: ["-c", "kill -KILL $$"]
            )
        )

        XCTAssertEqual(result.exitCode, 128 + SIGKILL)
        XCTAssertEqual(result.termination, .signaled(signal: SIGKILL))
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
