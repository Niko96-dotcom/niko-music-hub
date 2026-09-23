import AppCore
import Foundation

public enum StemSeparationHelperCopy {
    public static let missingLabel = "Stem helper missing"
    public static let missingBody = "demucs-mlx is not installed. Use Install Tools to add it, or choose an existing copy."
}

public enum DemucsMLXCommandBuilderError: LocalizedError, Equatable, Sendable {
    case missingExecutable

    public var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return StemSeparationHelperCopy.missingBody
        }
    }
}

public struct DemucsMLXCommandBuilder: Sendable {
    private let healthChecker: DemucsMLXHealthChecker
    private let locator: HelperToolLocator

    public init(
        healthChecker: DemucsMLXHealthChecker = DemucsMLXHealthChecker(),
        locator: HelperToolLocator = .standard()
    ) {
        self.healthChecker = healthChecker
        self.locator = locator
    }

    public func buildRequest(
        backendRequest: StemSeparationBackendRequest,
        settings: HelperToolSettings
    ) throws -> ExternalProcessRequest {
        guard let executableURL = healthChecker.resolvedExecutableURL(settings: settings) else {
            throw DemucsMLXCommandBuilderError.missingExecutable
        }

        var arguments: [String] = [
            backendRequest.inputURL.path,
            "--out",
            backendRequest.outputFolderURL.path,
            "-n",
            backendRequest.preset.demucsModelID,
            "--prefetch-tracks",
            "0",
            "--write-workers",
            "1"
        ]
        arguments.append(contentsOf: backendRequest.preset.demucsQualityArguments)

        return ExternalProcessRequest(
            executableURL: executableURL,
            arguments: arguments,
            environment: locator.processEnvironment(settings: settings)
        )
    }
}
