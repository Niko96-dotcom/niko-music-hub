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
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
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
}
