import Foundation

public protocol HelperDownloading: Sendable {
    /// Downloads url to destinationFile (overwriting). Returns the final URL after redirects.
    /// progress receives 0...1 when the size is known, nil otherwise.
    func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL
    func fetchText(_ url: URL) async throws -> String
}

/// Downloads over `URLSession`. A connection that drops or does not come up starts the request again from the
/// beginning, once after each of `retryDelays`; every other failure, and cancellation, ends it at once.
public struct URLSessionHelperDownloader: HelperDownloading, Sendable {
    private static let chunkSize = 64 * 1024
    /// URLSession's codes for a connection that dropped or did not come up, which a new attempt can cure.
    private static let droppedConnectionCodes: Set<URLError.Code> = [
        .networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed,
    ]

    private let session: URLSession
    private let retryDelays: [Duration]

    public init(session: URLSession = .shared, retryDelays: [Duration] = [.seconds(2), .seconds(5)]) {
        self.session = session
        self.retryDelays = retryDelays
    }

    public func fetchText(_ url: URL) async throws -> String {
        try await retryingDroppedConnections { try await fetchTextOnce(url) }
    }

    public func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try await retryingDroppedConnections { try await downloadOnce(url, to: destinationFile, progress: progress) }
    }

    private func retryingDroppedConnections<Value>(_ attempt: () async throws -> Value) async throws -> Value {
        var delays = retryDelays[...]
        while true {
            do {
                return try await attempt()
            } catch let dropped as DroppedConnection {
                guard let delay = delays.popFirst() else {
                    throw HelperInstallError.downloadFailed(dropped.detail)
                }
                try await Task.sleep(for: delay)
            }
        }
    }

    private func fetchTextOnce(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        let request = Self.request(for: url)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // URLSession reports network failures and task cancellation as URLError.
            try Task.checkCancellation()
            throw Self.failure(error, downloading: url)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): unexpected response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): HTTP \(http.statusCode)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): unreadable response")
        }
        return text
    }

    /// Writes the whole file again on each attempt.
    private func downloadOnce(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let request = Self.request(for: url)
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            // URLSession reports network failures and task cancellation as URLError.
            try Task.checkCancellation()
            throw Self.failure(error, downloading: url)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): unexpected response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): HTTP \(http.statusCode)")
        }

        let expectedLength = response.expectedContentLength
        let hasLength = expectedLength > 0

        let manager = FileManager.default
        try manager.createDirectory(
            at: destinationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if manager.fileExists(atPath: destinationFile.path) {
            try manager.removeItem(at: destinationFile)
        }
        _ = manager.createFile(atPath: destinationFile.path, contents: nil)

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: destinationFile)
        } catch {
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var downloaded: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(Self.chunkSize)
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= Self.chunkSize {
                    try handle.write(contentsOf: buffer)
                    downloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    try Task.checkCancellation()
                    if hasLength {
                        progress(min(1.0, Double(downloaded) / Double(expectedLength)))
                    } else {
                        progress(nil)
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HelperInstallError {
            throw error
        } catch {
            // URLSession byte-stream errors surface here; surface as a download failure
            // unless the task was cancelled.
            try Task.checkCancellation()
            throw Self.failure(error, downloading: url)
        }

        try Task.checkCancellation()
        if hasLength {
            progress(1.0)
        } else {
            progress(nil)
        }
        return response.url ?? url
    }

    /// A dropped connection is worth another attempt; any other URLSession error is the final download failure.
    private static func failure(_ error: any Error, downloading url: URL) -> any Error {
        let detail = "\(url.lastPathComponent): \(error.localizedDescription)"
        if let error = error as? URLError, droppedConnectionCodes.contains(error.code) {
            return DroppedConnection(detail: detail)
        }
        return HelperInstallError.downloadFailed(detail)
    }

    private struct DroppedConnection: Error {
        let detail: String
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // 60 s request timeout; resource timeout left at the session default (none imposed).
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}
