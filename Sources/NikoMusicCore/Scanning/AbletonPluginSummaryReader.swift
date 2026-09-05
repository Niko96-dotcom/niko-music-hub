import Foundation
import zlib

/// Read-only, bounded extraction of plug-in names from Live's gzip-compressed XML.
/// Unsupported or damaged sets still remain browsable and openable in Live.
enum AbletonPluginSummaryReader {
    static func pluginNames(at url: URL, maximumBytes: Int = 64 * 1024 * 1024) -> [String]? {
        guard let file = gzopen(url.path, "rb") else { return nil }
        defer { gzclose(file) }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            guard !Task.isCancelled else { return nil }
            let count = gzread(file, &chunk, UInt32(chunk.count))
            guard count >= 0 else { return nil }
            if count == 0 { break }
            guard data.count <= maximumBytes - Int(count) else { return nil }
            data.append(contentsOf: chunk.prefix(Int(count)))
        }
        var error: Int32 = Z_OK
        _ = gzerror(file, &error)
        guard error == Z_OK || error == Z_STREAM_END else { return nil }
        // Live sets do not need DTDs. Reject them rather than expanding entities.
        guard data.range(of: Data("<!DOCTYPE".utf8)) == nil,
              data.range(of: Data("<!ENTITY".utf8)) == nil else { return nil }
        let delegate = PluginNameDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.isAbleton else { return nil }
        return delegate.names.sorted()
    }
}

private final class PluginNameDelegate: NSObject, XMLParserDelegate {
    private var elements: [String] = []
    var names: Set<String> = []
    var isAbleton = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        if Task.isCancelled || elements.count >= 256 { parser.abortParsing(); return }
        if elements.isEmpty { isAbleton = elementName == "Ableton" }
        elements.append(elementName)
        let pluginContexts: Set<String> = ["VstPluginInfo", "Vst3PluginInfo", "AuPluginInfo"]
        guard elements.contains(where: pluginContexts.contains),
              ["PlugName", "Name", "PluginName"].contains(elementName),
              let rawName = attributeDict["Value"] else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name.count <= 256 { names.insert(name) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if !elements.isEmpty { elements.removeLast() }
    }
}
