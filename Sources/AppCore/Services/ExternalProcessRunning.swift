import Foundation

public struct ExternalProcessRequest: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]?
    public var timeoutSeconds: TimeInterval?

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
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

public enum ExternalProcessError: LocalizedError, Equatable, Sendable {
    case timedOut(executable: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(executable, seconds):
            return "\(executable) timed out after \(Int(seconds)) seconds."
        }
    }
}

public struct FoundationExternalProcessRunner: ExternalProcessRunning {
    public init() {}

    public func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        guard let timeoutSeconds = request.timeoutSeconds else {
            return try await runProcess(request)
        }

        return try await withThrowingTaskGroup(of: ExternalProcessResult.self) { group in
            group.addTask {
                try await runProcess(request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw ExternalProcessError.timedOut(
                    executable: request.executableURL.lastPathComponent,
                    seconds: timeoutSeconds
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func runProcess(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
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

        let completion = LockedProcessCompletion()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    outputData.append(outputPipe.fileHandleForReading.availableData)
                    errorData.append(errorPipe.fileHandleForReading.availableData)

                    completion.resume(
                        continuation,
                        with: .success(ExternalProcessResult(
                            exitCode: terminatedProcess.terminationStatus,
                            standardOutput: outputData.stringValue,
                            standardError: errorData.stringValue
                        ))
                    )
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    completion.resume(continuation, with: .failure(error))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

private final class LockedProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<ExternalProcessResult, any Error>,
        with result: Result<ExternalProcessResult, any Error>
    ) {
        let shouldResume = lock.withLock {
            guard !didResume else { return false }
            didResume = true
            return true
        }
        guard shouldResume else { return }

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
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
