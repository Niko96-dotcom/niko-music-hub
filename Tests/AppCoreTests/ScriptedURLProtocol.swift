import Foundation

/// A URL loader for tests: a session from `session(_:)` answers each request with the next reply of its script (the
/// last reply repeats), so a test can drop a connection and then serve the file, with no network.
final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        /// The connection fails before any response.
        case fail(URLError.Code)
        /// The response starts and half of the body arrives, then the connection fails.
        case failMidway(Data, URLError.Code)
        case status(Int)
        case body(Data)
    }

    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Reply]
        private var served = 0
        private let onRequest: @Sendable (Int) -> Void

        init(_ replies: [Reply], onRequest: @escaping @Sendable (_ requestNumber: Int) -> Void = { _ in }) {
            precondition(!replies.isEmpty)
            self.replies = replies
            self.onRequest = onRequest
        }

        var requestCount: Int {
            lock.withLock { served }
        }

        fileprivate func next() -> Reply {
            let (reply, number) = lock.withLock {
                served += 1
                return (replies.count > 1 ? replies.removeFirst() : replies[0], served)
            }
            onRequest(number)
            return reply
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scripts: [String: Script] = [:]

    /// A session whose requests to `https://<host>/…` follow `script`.
    static func session(_ script: Script) -> (session: URLSession, host: String) {
        let host = "\(UUID().uuidString.lowercased()).invalid"
        lock.withLock { scripts[host] = script }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedURLProtocol.self]
        return (URLSession(configuration: configuration), host)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        guard let script = Self.lock.withLock({ Self.scripts[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch script.next() {
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .failMidway(body, code):
            respond(status: 200, length: body.count)
            client?.urlProtocol(self, didLoad: body.prefix(body.count / 2))
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .status(code):
            respond(status: code, length: 0)
            client?.urlProtocolDidFinishLoading(self)
        case let .body(body):
            respond(status: 200, length: body.count)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, length: Int) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(length)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}
