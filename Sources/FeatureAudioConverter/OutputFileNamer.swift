import AppCore
import Foundation

public struct OutputFileNamer: Sendable {
    public init() {}

    public func plannedOutputURL(
        for outputDirectory: URL,
        sourceURL: URL,
        preset: AudioPreset,
        existingFileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let sourceName = Self.truncatedStem(sourceURL.deletingPathExtension().lastPathComponent)
        let presetSuffix = "\(preset.sampleRate)Hz \(preset.bitDepth)bit"
        let baseName = "\(sourceName) - \(presetSuffix)"
        var candidate = outputDirectory.appendingPathComponent("\(baseName).wav")

        var counter = 2
        while existingFileExists(candidate) {
            candidate = outputDirectory.appendingPathComponent("\(baseName) \(counter).wav")
            counter += 1
        }

        return candidate
    }

    /// UTF-8 bytes kept from the source stem. APFS allows 255 bytes per name, and the
    /// converters add about 75 bytes (preset suffix, counter, ".<UUID>.tmp.wav").
    static let maxStemBytes = 150

    private static func truncatedStem(_ stem: String) -> String {
        guard stem.utf8.count > maxStemBytes else { return stem }
        // Cut at a character boundary so no multibyte character is split.
        var truncated = ""
        var byteCount = 0
        for character in stem {
            let characterBytes = character.utf8.count
            guard byteCount + characterBytes <= maxStemBytes else { break }
            truncated.append(character)
            byteCount += characterBytes
        }
        return truncated.trimmingCharacters(in: .whitespaces)
    }
}
