import Foundation

public struct StemSeparationRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputRootURL: URL
    public let preset: StemSeparationPreset
    public let title: String?

    public init(
        inputURL: URL,
        outputRootURL: URL,
        preset: StemSeparationPreset,
        title: String? = nil
    ) {
        self.inputURL = inputURL
        self.outputRootURL = outputRootURL
        self.preset = preset
        self.title = title
    }
}

public struct StemSeparationBackendRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputFolderURL: URL
    public let preset: StemSeparationPreset

    public init(
        inputURL: URL,
        outputFolderURL: URL,
        preset: StemSeparationPreset
    ) {
        self.inputURL = inputURL
        self.outputFolderURL = outputFolderURL
        self.preset = preset
    }
}

public enum StemSeparationResult: Equatable, Sendable {
    case success(outputFolderURL: URL, stems: [StemOutput])
    case failed(message: String)
    case canceled
}
