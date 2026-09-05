import Foundation

public struct CPRPluginSummary: Equatable, Sendable {
    public let pluginNames: [String]
    public let source: String

    public init(pluginNames: [String], source: String) {
        self.pluginNames = pluginNames
        self.source = source
    }

    public static let empty = CPRPluginSummary(pluginNames: [], source: "empty")
}

/// Read-only CPR plugin listing with mtime-keyed cache and graceful degradation.
public enum CPRPluginSummaryService {
    private static let maxCacheEntries = 128
    /// Skip in-memory parsing above this size; subprocess path is unaffected.
    private static let maxInMemoryParseBytes = 8 * 1024 * 1024
    private static let boundedReadChunkBytes = 256 * 1024
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [String: CacheEntry] = [:]

    private struct CacheEntry: Sendable {
        let modifiedAt: Date
        let summary: CPRPluginSummary
    }

    public static func loadPlugins(
        cprURL: URL,
        fileManager: FileManager = .default,
        subprocessRunner: @escaping @Sendable (URL) async -> [String]? = { _ in nil }
    ) async -> CPRPluginSummary {
        let standard = cprURL.standardizedFileURL
        let cacheKey = standard.path
        let modifiedAt = (try? standard.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast

        if let cachedSummary = cacheLock.withLock({ () -> CPRPluginSummary? in
            guard let cached = cache[cacheKey], cached.modifiedAt == modifiedAt else { return nil }
            return cached.summary
        }) {
            return cachedSummary
        }
        guard !Task.isCancelled else { return .empty }

        let summary: CPRPluginSummary
        if !Task.isCancelled,
           let names = await subprocessRunner(standard),
           !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "subprocess")
        } else if Task.isCancelled {
            return .empty
        } else if let names = parseEmbeddedMarker(in: standard, fileManager: fileManager), !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "marker")
        } else if fileSize(at: standard, fileManager: fileManager) <= maxInMemoryParseBytes,
                  let names = parsePluginNamesFromData(standard, fileManager: fileManager),
                  !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "parser")
        } else {
            summary = .empty
        }

        guard !Task.isCancelled else { return .empty }

        cacheLock.withLock {
            cache[cacheKey] = CacheEntry(modifiedAt: modifiedAt, summary: summary)
            if cache.count > maxCacheEntries,
               let keyToRemove = cache.min(by: { $0.value.modifiedAt < $1.value.modifiedAt })?.key {
                cache.removeValue(forKey: keyToRemove)
            }
        }
        return summary
    }

    public static func clearCache() {
        cacheLock.withLock {
            cache.removeAll()
        }
    }

    static func parseEmbeddedMarker(in url: URL, fileManager: FileManager) -> [String]? {
        guard let data = readBoundedPrefixAndSuffix(at: url, fileManager: fileManager),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        guard let range = text.range(of: "NIKO_PLUGINS:") else { return nil }
        let tail = text[range.upperBound...]
        // CPR/project files are binary; the marker list is terminated by a null byte
        // or a newline/carriage return.
        let end = tail.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) ?? tail.endIndex
        let list = tail[..<end]
        let names = list.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    static func parsePluginNamesFromData(_ url: URL, fileManager: FileManager) -> [String]? {
        guard let data = readBoundedPrefixAndSuffix(at: url, fileManager: fileManager) else { return nil }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        var names: Set<String> = []
        let patterns = [
            #"Name=\"([^\"]{2,80})\""#,
            #"<Plugin[^>]*name=\"([^\"]{2,80})\""#,
            #"VST3:\s*([A-Za-z0-9][A-Za-z0-9 _.\-]{1,60})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let capture = Range(match.range(at: 1), in: text) else { return }
                let name = String(text[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2, !name.localizedCaseInsensitiveContains("cubase") {
                    names.insert(name)
                }
            }
        }
        return names.isEmpty ? nil : Array(names)
    }

    static func fileSize(at url: URL, fileManager: FileManager) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }

    /// Reads the first and last bounded windows for marker/regex heuristics without loading whole CPR files.
    static func readBoundedPrefixAndSuffix(at url: URL, fileManager: FileManager) -> Data? {
        let size = fileSize(at: url, fileManager: fileManager)
        guard size > 0 else { return nil }
        if size <= UInt64(boundedReadChunkBytes) * 2 {
            return fileManager.contents(atPath: url.path)
        }
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        if let prefix = try? handle.read(upToCount: boundedReadChunkBytes) {
            data.append(prefix)
        }
        let suffixOffset = Int64(size) - Int64(boundedReadChunkBytes)
        if suffixOffset > Int64(boundedReadChunkBytes),
           (try? handle.seek(toOffset: UInt64(suffixOffset))) != nil,
           let suffix = try? handle.read(upToCount: boundedReadChunkBytes) {
            data.append(suffix)
        }
        return data.isEmpty ? nil : data
    }

    public static func parsePluginListOutput(_ output: String) -> [String]? {
        let names = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return names.isEmpty ? nil : names
    }
}
