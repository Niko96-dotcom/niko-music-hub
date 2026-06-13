import AppCore
import Foundation

public enum DemucsMLXCommandBuilderError: LocalizedError, Equatable, Sendable {
    case missingExecutable
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
        } else if let detected = DemucsMLXHealthChecker.detectExecutable(fileExists: { _ in false }) {
            executableURL = detected
        } else {
            throw DemucsMLXCommandBuilderError.missingExecutable
        }

        let arguments: [String] = [
            backendRequest.inputURL.path,
            "--out",
            backendRequest.outputFolderURL.path,
            "--model",
            backendRequest.preset.demucsModelID
        ]

        return ExternalProcessRequest(
            executableURL: executableURL,
            arguments: arguments
        )
    }
}
