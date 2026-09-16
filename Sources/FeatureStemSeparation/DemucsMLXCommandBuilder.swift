import AppCore
import Foundation

public enum StemSeparationHelperCopy {
    public static let missingLabel = "Stem helper missing"
    public static let missingBody = "demucs-mlx is not available at the configured path. Stem Separation cannot start until you choose the binary."
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

    public init(healthChecker: DemucsMLXHealthChecker = DemucsMLXHealthChecker()) {
        self.healthChecker = healthChecker
    }

    public func buildRequest(
        backendRequest: StemSeparationBackendRequest,
        settings: HelperToolSettings
    ) throws -> ExternalProcessRequest {
        let executableURL: URL
        if let configured = settings.demucsMlx {
            executableURL = configured
        } else if let detected = healthChecker.resolvedExecutableURL(settings: settings) {
            executableURL = detected
        } else {
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
            arguments: arguments
        )
    }
}
