import AppCore
import Foundation

public struct DemucsMLXHealthChecker: Sendable {
    private let runner: any ExternalProcessRunning
    private let fileExists: @Sendable (String) -> Bool
    private let locator: HelperToolLocator

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        locator: HelperToolLocator = .standard()
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.locator = locator
    }

    public func availability(settings: HelperToolSettings) async -> StemBackendHealth {
        guard let executableURL = resolvedExecutableURL(settings: settings) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: executableURL,
            arguments: ["--list-models"],
            timeoutSeconds: 30
        )

        do {
            let result = try await runner.run(request)
            guard result.exitCode == 0 else {
                return .unusable(message: diagnosticMessage(from: result))
            }
            let version = versionLine(from: result.standardOutput)
            return .ready(version: version)
        } catch {
            return .unusable(message: error.localizedDescription)
        }
    }

    public func resolvedExecutableURL(settings: HelperToolSettings) -> URL? {
        locator.resolve(.demucsMlx, settings: settings)
    }

    private func versionLine(from output: String) -> String {
        let firstModel = output
            .split(whereSeparator: \.isNewline)
            .first?
            .split(separator: "\t")
            .first
            .map(String.init)
        return firstModel.map { "demucs-mlx (\($0) available)" } ?? "demucs-mlx"
    }

    private func diagnosticMessage(from result: ExternalProcessResult) -> String {
        let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "demucs-mlx exited with code \(result.exitCode)." : trimmed
    }
}
