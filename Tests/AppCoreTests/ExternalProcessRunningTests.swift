@testable import AppCore
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

    func testTimeoutRacesPromptChildExitAcrossConcurrentRuns() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))

        let runner = FoundationExternalProcessRunner(terminationGraceSeconds: 0.05)
        let request = ExternalProcessRequest(
            executableURL: perlURL,
            arguments: [
                "-e",
                """
                $| = 1;
                $SIG{TERM} = sub { print \"terminating\\n\"; exit 0; };
                print \"ready\\n\";
                sleep 10;
                """
            ],
            timeoutSeconds: 0.03
        )
        let expectedError = ExternalProcessError.timedOut(executable: "perl", seconds: 0.03)

        // The timeout runs on a global queue while the exited child is flushed
        // on the I/O queue. Repeating this in parallel makes their cleanup race
        // observable under Thread Sanitizer without relying on a long sleep.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        _ = try await runner.run(request)
                        throw ExternalProcessRaceTestError.expectedTimeout
                    } catch let error as ExternalProcessError {
                        guard error == expectedError else { throw error }
                    }
                }
            }
            try await group.waitForAll()
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

    func testStreamingDecodesUTF8ScalarSplitAcrossReadsWithStreamIsolation() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let runner = FoundationExternalProcessRunner()
        let stdoutChunks = LockedStringArray()
        let stderrChunks = LockedStringArray()

        // The two bytes of "é" (U+00E9) are written ~0.2 s apart, so they
        // arrive in separate pipe reads. A per-read strict decode would drop
        // both halves; the stream must reassemble the scalar instead.
        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: perlURL,
                arguments: ["-e", "binmode STDOUT, ':raw'; binmode STDERR, ':raw'; $|=1; print STDOUT \"\\xC3\"; select undef, undef, undef, 0.2; print STDOUT \"\\xA9\"; print STDERR \"plain-err\\n\";"]
            ),
            onStandardOutput: { chunk in
                stdoutChunks.append(chunk)
            },
            onStandardError: { chunk in
                stderrChunks.append(chunk)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stdoutChunks.joined(), "é")
        XCTAssertEqual(result.standardOutput, "é")
        XCTAssertEqual(stderrChunks.joined(), "plain-err\n")
        XCTAssertEqual(result.standardError, "plain-err\n")
        XCTAssertFalse(stdoutChunks.joined().contains("plain-err"))
        XCTAssertFalse(stderrChunks.joined().contains("é"))
    }

    func testStreamingDecoderEmitsMalformedPrefixPromptly() {
        // Direct behavioral test for bytes FF 4F 4B 0A: the old whole-prefix
        // strict check retained "OK\n" as a fake incomplete tail and delayed
        // valid text until a later read or flush. Only a truly incomplete
        // trailing scalar may be held.
        let decoder = StreamingUTF8Decoder()
        let chunk = decoder.decode(Data([0xFF, 0x4F, 0x4B, 0x0A]))
        XCTAssertTrue(
            chunk.contains("OK"),
            "valid ASCII after an invalid byte must emit promptly, got \(chunk.debugDescription)"
        )
        XCTAssertTrue(
            chunk.contains("�"),
            "malformed byte must surface lossily in the same chunk, got \(chunk.debugDescription)"
        )
        XCTAssertEqual(decoder.flush(), "", "complete ASCII suffix must leave nothing pending")

        // An invalid byte alone emits immediately and does not pin the next read.
        let split = StreamingUTF8Decoder()
        XCTAssertEqual(split.decode(Data([0xFF])), "�")
        XCTAssertEqual(split.decode(Data([0x4F, 0x4B, 0x0A])), "OK\n")
        XCTAssertEqual(split.flush(), "")

        // A genuinely split scalar is still held across reads, then emitted whole.
        let scalar = StreamingUTF8Decoder()
        XCTAssertEqual(scalar.decode(Data([0xC3])), "")
        XCTAssertEqual(scalar.decode(Data([0xA9])), "é")
        XCTAssertEqual(scalar.flush(), "")
    }

    func testStreamingDecoderRejectsRestrictedSecondBytesPromptly() {
        let invalidPrefixes: [[UInt8]] = [
            [0xE0, 0x80],
            [0xED, 0xA0],
            [0xF0, 0x80],
            [0xF4, 0x90],
        ]
        for prefix in invalidPrefixes {
            let decoder = StreamingUTF8Decoder()
            let chunk = decoder.decode(Data(prefix))
            XCTAssertTrue(
                chunk.contains("�"),
                "prefix \(prefix) must emit replacement promptly, got \(chunk.debugDescription)"
            )
            XCTAssertEqual(
                decoder.flush(),
                "",
                "prefix \(prefix) must leave nothing pending"
            )
        }

        // Malformed restricted prefix plus ASCII emits ASCII in the same call.
        for prefix in invalidPrefixes {
            let decoder = StreamingUTF8Decoder()
            let chunk = decoder.decode(Data(prefix + [0x41]))
            XCTAssertTrue(
                chunk.contains("�"),
                "prefix \(prefix) plus ASCII must surface replacement, got \(chunk.debugDescription)"
            )
            XCTAssertTrue(
                chunk.contains("A"),
                "prefix \(prefix) must not hold trailing ASCII, got \(chunk.debugDescription)"
            )
            XCTAssertEqual(decoder.flush(), "")
        }

        // An invalid prefix does not pin the next read.
        for prefix in invalidPrefixes {
            let decoder = StreamingUTF8Decoder()
            _ = decoder.decode(Data(prefix))
            XCTAssertEqual(decoder.decode(Data([0x42])), "B")
            XCTAssertEqual(decoder.flush(), "")
        }

        // Split restricted second bytes also emit promptly on arrival.
        let splitInvalid: [(first: [UInt8], second: [UInt8])] = [
            ([0xE0], [0x80]),
            ([0xED], [0xA0]),
            ([0xF0], [0x80]),
            ([0xF4], [0x90]),
        ]
        for pair in splitInvalid {
            let decoder = StreamingUTF8Decoder()
            XCTAssertEqual(decoder.decode(Data(pair.first)), "")
            let chunk = decoder.decode(Data(pair.second))
            XCTAssertTrue(
                chunk.contains("�"),
                "split prefix \(pair.first)+\(pair.second) must emit replacement, got \(chunk.debugDescription)"
            )
            XCTAssertEqual(decoder.flush(), "")
        }

        // Valid boundary second bytes remain pending until completed.
        let e0 = StreamingUTF8Decoder()
        XCTAssertEqual(e0.decode(Data([0xE0])), "")
        XCTAssertEqual(e0.decode(Data([0xA0])), "")
        XCTAssertEqual(e0.decode(Data([0x80])), "\u{0800}")
        XCTAssertEqual(e0.flush(), "")

        let ed = StreamingUTF8Decoder()
        XCTAssertEqual(ed.decode(Data([0xED])), "")
        XCTAssertEqual(ed.decode(Data([0x9F])), "")
        XCTAssertEqual(ed.decode(Data([0xBF])), "\u{D7FF}")
        XCTAssertEqual(ed.flush(), "")

        let f0 = StreamingUTF8Decoder()
        XCTAssertEqual(f0.decode(Data([0xF0])), "")
        XCTAssertEqual(f0.decode(Data([0x90])), "")
        XCTAssertEqual(f0.decode(Data([0x80, 0x80])), "\u{10000}")
        XCTAssertEqual(f0.flush(), "")

        let f4 = StreamingUTF8Decoder()
        XCTAssertEqual(f4.decode(Data([0xF4])), "")
        XCTAssertEqual(f4.decode(Data([0x8F])), "")
        XCTAssertEqual(f4.decode(Data([0xBF, 0xBF])), "\u{10FFFF}")
        XCTAssertEqual(f4.flush(), "")
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

    /// Swift concurrency / dispatch worker threads block asynchronous signals and
    /// `posix_spawn` inherits the caller's mask. The child must start with an empty
    /// mask, or the graceful SIGTERM never lands and only the SIGKILL escalation works.
    func testTaskCancellationDeliversSIGTERMBeforeKillEscalation() async throws {
        let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: perlURL.path))
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-sigterm-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let runner = FoundationExternalProcessRunner(terminationGraceSeconds: 30)
        let task = Task.detached {
            try await runner.run(
                ExternalProcessRequest(
                    executableURL: perlURL,
                    arguments: [
                        "-e",
                        "open($fh, '>', $ARGV[0]) or die $!; print $fh $$; close($fh); sleep 10;",
                        pidFile.path
                    ]
                )
            )
        }
        for _ in 0..<200 where (try? String(contentsOf: pidFile, encoding: .utf8))?.isEmpty ?? true {
            try await Task.sleep(for: .milliseconds(10))
        }
        let childPID = try XCTUnwrap(pid_t(String(contentsOf: pidFile, encoding: .utf8)))

        task.cancel()
        _ = try? await task.value

        for _ in 0..<200 where kill(childPID, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(childPID, 0), -1, "SIGTERM did not reach the helper process")
        XCTAssertEqual(errno, ESRCH)
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

private enum ExternalProcessRaceTestError: Error {
    case expectedTimeout
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
