import Foundation

public struct ExternalProcessRequest: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]?

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }
}

public struct ExternalProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ExternalProcessRunning: Sendable {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult
}

public struct FoundationExternalProcessRunner: ExternalProcessRunning {
    public init() {}

    public func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        if let environment = request.environment {
            process.environment = environment
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let outputData = LockedProcessData()
        let errorData = LockedProcessData()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputData.append(outputPipe.fileHandleForReading.availableData)
        errorData.append(errorPipe.fileHandleForReading.availableData)

        return ExternalProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: outputData.stringValue,
            standardError: errorData.stringValue
        )
    }
}

private final class LockedProcessData: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks = Data()

    var stringValue: String {
        lock.withLock {
            String(data: chunks, encoding: .utf8) ?? ""
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            chunks.append(data)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
