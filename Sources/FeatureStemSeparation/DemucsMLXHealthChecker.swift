import AppCore
import Foundation

public struct DemucsMLXHealthChecker: Sendable {
    public static let knownExecutablePaths: [String] = [
        "\(NSHomeDirectory())/.local/bin/demucs-mlx",
        "/opt/homebrew/bin/demucs-mlx",
        "/usr/local/bin/demucs-mlx"
    ]

    public static let defaultModelCacheURL: URL = {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("demucs-mlx", isDirectory: true)
    }()

    private let runner: any ExternalProcessRunning
    private let fileExists: @Sendable (String) -> Bool
    private let modelCacheURL: URL

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        modelCacheURL: URL = Self.defaultModelCacheURL
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.modelCacheURL = modelCacheURL
    }

    public func availability(settings: HelperToolSettings) async -> StemBackendHealth {
        guard let executableURL = resolvedExecutableURL(settings: settings) else {
            return .missing
        }
        guard fileExists(executableURL.path) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: executableURL,
            arguments: ["--version"]
        )

        do {
            let result = try await runner.run(request)
            guard result.exitCode == 0 else {
                return .unusable(message: diagnosticMessage(from: result))
            }
            let version = versionLine(from: result.standardOutput)
            guard modelCacheExists() else {
                return .modelCacheMissing
            }
            return .ready(version: version)
        } catch {
            return .unusable(message: error.localizedDescription)
        }
    }

    public func resolvedExecutableURL(settings: HelperToolSettings) -> URL? {
        if let configured = settings.demucsMlx, fileExists(configured.path) {
            return configured
        }
        return Self.detectExecutable(fileExists: fileExists)
    }

    public static func detectExecutable(
        fileExists: @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> URL? {
        for path in knownExecutablePaths where fileExists(path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func modelCacheExists() -> Bool {
        fileExists(modelCacheURL.path)
    }

    private func versionLine(from output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "demucs-mlx"
    }

    private func diagnosticMessage(from result: ExternalProcessResult) -> String {
        let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "demucs-mlx exited with code \(result.exitCode)." : trimmed
    }
}
