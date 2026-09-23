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

public struct URLSessionHelperDownloader: HelperDownloading, Sendable {
    private static let chunkSize = 64 * 1024

    public init() {}

    public func fetchText(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        let request = Self.request(for: url)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
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

    public func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let request = Self.request(for: url)
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
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
            throw HelperInstallError.downloadFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }

        try Task.checkCancellation()
        if hasLength {
            progress(1.0)
        } else {
            progress(nil)
        }
        return response.url ?? url
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // 60 s request timeout; resource timeout left at the session default (none imposed).
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}
