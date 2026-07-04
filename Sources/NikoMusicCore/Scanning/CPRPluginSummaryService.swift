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
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [String: CacheEntry] = [:]

    private struct CacheEntry: Sendable {
        let modifiedAt: Date
        let summary: CPRPluginSummary
    }

    public static func loadPlugins(
        cprURL: URL,
        fileManager: FileManager = .default,
        subprocessRunner: @escaping @Sendable (URL) -> [String]? = { runCubaseProjectPlugins(cprURL: $0) }
    ) -> CPRPluginSummary {
        let standard = cprURL.standardizedFileURL
        let cacheKey = standard.path
        let modifiedAt = (try? standard.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast

        cacheLock.lock()
        if let cached = cache[cacheKey], cached.modifiedAt == modifiedAt {
            let summary = cached.summary
            cacheLock.unlock()
            return summary
        }
        cacheLock.unlock()

        let summary: CPRPluginSummary
        if let names = subprocessRunner(standard), !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "subprocess")
        } else if let names = parseEmbeddedMarker(in: standard, fileManager: fileManager), !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "marker")
        } else if let names = parsePluginNamesFromData(standard, fileManager: fileManager), !names.isEmpty {
            summary = CPRPluginSummary(pluginNames: names.sorted(), source: "parser")
        } else {
            summary = .empty
        }

        cacheLock.lock()
        cache[cacheKey] = CacheEntry(modifiedAt: modifiedAt, summary: summary)
        if cache.count > maxCacheEntries, let keyToRemove = cache.keys.first {
            cache.removeValue(forKey: keyToRemove)
        }
        cacheLock.unlock()
        return summary
    }

    public static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    static func parseEmbeddedMarker(in url: URL, fileManager: FileManager) -> [String]? {
        guard let data = fileManager.contents(atPath: url.path),
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
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
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

    @usableFromInline static func runCubaseProjectPlugins(cprURL: URL) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cubase-project-plugins", cprURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let names = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return names.isEmpty ? nil : names
    }
}
