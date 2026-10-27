import AppCore
import Foundation
import XCTest

final class URLSessionHelperDownloaderTests: XCTestCase {
    func testRequestErrorsBecomeDownloadFailed() async throws {
        // An unsupported scheme fails inside URLSession without any network access.
        let url = try XCTUnwrap(URL(string: "nmh-unsupported://example.invalid/tool.sha256"))
        let downloader = URLSessionHelperDownloader()
        do {
            _ = try await downloader.fetchText(url)
            XCTFail("fetchText should throw")
        } catch let error as HelperInstallError {
            guard case .downloadFailed = error else { return XCTFail("unexpected error \(error)") }
        }
        let destination = makeDestination()
        do {
            _ = try await downloader.download(url, to: destination, progress: { _ in })
            XCTFail("download should throw")
        } catch let error as HelperInstallError {
            guard case .downloadFailed = error else { return XCTFail("unexpected error \(error)") }
        }
    }

    /// The first attempt drops halfway and the second cannot connect; the third writes the whole file, not the
    /// first attempt's half followed by it.
    func testDownloadStartsAgainAfterADroppedConnection() async throws {
        let file = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0) })
        let script = ScriptedURLProtocol.Script([
            .failMidway(file, .networkConnectionLost),
            .fail(.cannotConnectToHost),
            .body(file),
        ])
        let (session, host) = ScriptedURLProtocol.session(script)
        let downloader = URLSessionHelperDownloader(session: session, retryDelays: [.zero, .zero])
        let destination = makeDestination()

        _ = try await downloader.download(try fileURL(host, "ffmpeg.zip"), to: destination, progress: { _ in })

        XCTAssertEqual(try Data(contentsOf: destination), file)
        XCTAssertEqual(script.requestCount, 3)
    }

    func testFetchTextStartsAgainAfterADroppedConnection() async throws {
        let script = ScriptedURLProtocol.Script([.fail(.timedOut), .body(Data(#"{"tag_name": "2026.10.26"}"#.utf8))])
        let (session, host) = ScriptedURLProtocol.session(script)
        let downloader = URLSessionHelperDownloader(session: session, retryDelays: [.zero])

        let text = try await downloader.fetchText(try fileURL(host, "latest"))

        XCTAssertEqual(text, #"{"tag_name": "2026.10.26"}"#)
        XCTAssertEqual(script.requestCount, 2)
    }

    func testDroppedConnectionsStopAfterTheLastRetry() async throws {
        let script = ScriptedURLProtocol.Script([.fail(.networkConnectionLost)])
        let (session, host) = ScriptedURLProtocol.session(script)
        let downloader = URLSessionHelperDownloader(session: session, retryDelays: [.zero, .zero])

        do {
            _ = try await downloader.download(try fileURL(host, "uv.tar.gz"), to: makeDestination(), progress: { _ in })
            XCTFail("download should throw")
        } catch HelperInstallError.downloadFailed(let detail) {
            XCTAssertTrue(detail.hasPrefix("uv.tar.gz: "), detail)
        }
        XCTAssertEqual(script.requestCount, 3, "one attempt and one after each retry delay")
    }

    /// An HTTP error or a failed secure connection is no dropped connection: a new attempt cannot cure it.
    func testOtherFailuresAreNotRetried() async throws {
        for reply in [ScriptedURLProtocol.Reply.status(404), .fail(.secureConnectionFailed)] {
            let script = ScriptedURLProtocol.Script([reply])
            let (session, host) = ScriptedURLProtocol.session(script)
            let downloader = URLSessionHelperDownloader(session: session, retryDelays: [.zero, .zero])

            do {
                _ = try await downloader.download(try fileURL(host, "ffprobe.zip"), to: makeDestination(), progress: { _ in })
                XCTFail("download should throw for \(reply)")
            } catch let error as HelperInstallError {
                guard case .downloadFailed = error else { return XCTFail("unexpected error \(error)") }
            }
            XCTAssertEqual(script.requestCount, 1, "\(reply)")
        }
    }

    /// Cancel lands during the dropped request or during the 60 s wait after it; either way the fetch ends with
    /// `CancellationError` and starts no further attempt.
    func testCancelWhileRetryingStartsNoFurtherAttempt() async throws {
        let firstRequest = expectation(description: "the first attempt reached the server")
        let script = ScriptedURLProtocol.Script([.fail(.networkConnectionLost)]) { number in
            if number == 1 { firstRequest.fulfill() }
        }
        let (session, host) = ScriptedURLProtocol.session(script)
        let downloader = URLSessionHelperDownloader(session: session, retryDelays: [.seconds(60)])
        let url = try fileURL(host, "latest")
        let fetch = Task { try await downloader.fetchText(url) }

        await fulfillment(of: [firstRequest], timeout: 10)
        fetch.cancel()

        do {
            _ = try await fetch.value
            XCTFail("fetchText should throw")
        } catch is CancellationError {}
        XCTAssertEqual(script.requestCount, 1)
    }

    private func fileURL(_ host: String, _ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://\(host)/download/\(name)"))
    }

    private func makeDestination() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("tool")
    }
}
