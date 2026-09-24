import Darwin
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

public enum ExternalProcessTermination: Equatable, Sendable {
    case exited(code: Int32)
    case signaled(signal: Int32)
}

public struct ExternalProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String
    public var termination: ExternalProcessTermination
    public var standardOutputWasTruncated: Bool
    public var standardErrorWasTruncated: Bool

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        termination: ExternalProcessTermination? = nil,
        standardOutputWasTruncated: Bool = false,
        standardErrorWasTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.termination = termination ?? .exited(code: exitCode)
        self.standardOutputWasTruncated = standardOutputWasTruncated
        self.standardErrorWasTruncated = standardErrorWasTruncated
    }
}

public protocol ExternalProcessRunning: Sendable {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult
}

public protocol StreamingExternalProcessRunning: ExternalProcessRunning {
    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult
}

public enum ExternalProcessError: LocalizedError, Equatable, Sendable {
    case timedOut(executable: String, seconds: TimeInterval)
    case launchFailed(executable: String, message: String)
    case waitFailed(executable: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(executable, seconds):
            return "\(executable) timed out after \(seconds.formatted(.number.precision(.fractionLength(0...3)))) seconds."
        case let .launchFailed(executable, message):
            return "Could not launch \(executable): \(message)"
        case let .waitFailed(executable, message):
            return "Could not supervise \(executable): \(message)"
        }
    }
}

/// Canonical subprocess supervisor for production helper tools.
///
/// Each helper starts in a dedicated process group so cancellation and timeout
/// terminate descendants as well as the direct child. Awaiters complete at the
/// deadline; cleanup continues independently and escalates from TERM to KILL.
public struct FoundationExternalProcessRunner: StreamingExternalProcessRunning {
    public static let defaultMaximumCapturedOutputBytes = 1_048_576

    private let maximumCapturedOutputBytes: Int
    private let terminationGraceSeconds: TimeInterval

    public init(
        maximumCapturedOutputBytes: Int = defaultMaximumCapturedOutputBytes,
        terminationGraceSeconds: TimeInterval = 0.25
    ) {
        self.maximumCapturedOutputBytes = max(1, maximumCapturedOutputBytes)
        self.terminationGraceSeconds = max(0, terminationGraceSeconds)
    }

    public func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    public func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        try Task.checkCancellation()
        let execution = POSIXProcessExecution(
            request: request,
            maximumCapturedOutputBytes: maximumCapturedOutputBytes,
            terminationGraceSeconds: terminationGraceSeconds,
            onStandardOutput: onStandardOutput,
            onStandardError: onStandardError
        )
        return try await withTaskCancellationHandler {
            try await execution.start()
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class POSIXProcessExecution: @unchecked Sendable {
    private enum Stream {
        case standardOutput
        case standardError
    }

    private let request: ExternalProcessRequest
    private let terminationGraceSeconds: TimeInterval
    private let onStandardOutput: @Sendable (String) -> Void
    private let onStandardError: @Sendable (String) -> Void
    private let standardOutput: BoundedProcessData
    private let standardError: BoundedProcessData
    // Incremental UTF-8 state, one decoder per pipe. Every touch happens on
    // `ioQueue` (read events and the normal-EOF flush), which serializes
    // access without extra locking.
    private let standardOutputDecoder = StreamingUTF8Decoder()
    private let standardErrorDecoder = StreamingUTF8Decoder()
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.nikomusichub.process-io", qos: .utility)
    private let waitQueue = DispatchQueue(label: "com.nikomusichub.process-wait", qos: .utility)

    private var continuation: CheckedContinuation<ExternalProcessResult, any Error>?
    private var processID: pid_t?
    private var standardOutputSource: DispatchSourceRead?
    private var standardErrorSource: DispatchSourceRead?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completionResult: Result<ExternalProcessResult, any Error>?
    private var didFinish = false

    init(
        request: ExternalProcessRequest,
        maximumCapturedOutputBytes: Int,
        terminationGraceSeconds: TimeInterval,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) {
        self.request = request
        self.terminationGraceSeconds = terminationGraceSeconds
        self.onStandardOutput = onStandardOutput
        self.onStandardError = onStandardError
        self.standardOutput = BoundedProcessData(limit: maximumCapturedOutputBytes)
        self.standardError = BoundedProcessData(limit: maximumCapturedOutputBytes)
    }

    func start() async throws -> ExternalProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let pendingResult = lock.withLock { () -> Result<ExternalProcessResult, any Error>? in
                self.continuation = continuation
                return completionResult
            }
            if let pendingResult {
                resume(with: pendingResult)
                return
            }

            do {
                try launch()
            } catch {
                finish(.failure(error), terminateRunningProcess: false)
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()), terminateRunningProcess: true)
    }

    private func launch() throws {
        var standardOutputPipe = [Int32](repeating: -1, count: 2)
        var standardErrorPipe = [Int32](repeating: -1, count: 2)
        guard makePipe(&standardOutputPipe) == 0 else {
            throw launchError(errno)
        }
        guard makePipe(&standardErrorPipe) == 0 else {
            closePair(standardOutputPipe)
            throw launchError(errno)
        }
        // Concurrent launches: a second child spawned while these pipes are open
        // must not inherit them, or the first child's EOF is delayed until the
        // second exits. The dup2 file actions below still hand the child its own
        // stdout/stderr (dup2 clears close-on-exec on the target descriptors).
        for descriptor in standardOutputPipe + standardErrorPipe {
            setCloseOnExec(descriptor)
        }

        var actions: posix_spawn_file_actions_t? = nil
        var attributes: posix_spawnattr_t? = nil
        guard posix_spawn_file_actions_init(&actions) == 0,
              posix_spawnattr_init(&attributes) == 0 else {
            closePair(standardOutputPipe)
            closePair(standardErrorPipe)
            throw launchError(errno)
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        posix_spawn_file_actions_adddup2(&actions, standardOutputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardErrorPipe[1], STDERR_FILENO)
        for descriptor in standardOutputPipe + standardErrorPipe {
            posix_spawn_file_actions_addclose(&actions, descriptor)
        }

        // The launching thread is a concurrency/dispatch worker whose signal mask blocks
        // asynchronous signals, and the child inherits it. Start helpers with an empty
        // mask and default handlers so the SIGTERM step of termination is delivered.
        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        posix_spawnattr_setsigmask(&attributes, &emptySignalMask)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        posix_spawnattr_setflags(&attributes, flags)
        posix_spawnattr_setpgroup(&attributes, 0)

        let executablePath = request.executableURL.path
        let argumentStorage = ([executablePath] + request.arguments).map { strdup($0)! }
        defer { argumentStorage.forEach { free($0) } }
        var arguments: [UnsafeMutablePointer<CChar>?] = argumentStorage.map { $0 } + [nil]

        var environmentStorage: [UnsafeMutablePointer<CChar>?] = []
        if let requestedEnvironment = request.environment {
            environmentStorage = requestedEnvironment
                .sorted(by: { $0.key < $1.key })
                .map { strdup("\($0.key)=\($0.value)")! }
                .map { Optional($0) } + [nil]
        }
        defer { environmentStorage.dropLast().forEach { free($0) } }

        var childPID: pid_t = 0
        let spawnStatus: Int32 = if request.environment != nil {
            environmentStorage.withUnsafeMutableBufferPointer { environmentBuffer in
                executablePath.withCString { path in
                    posix_spawn(
                        &childPID,
                        path,
                        &actions,
                        &attributes,
                        &arguments,
                        environmentBuffer.baseAddress
                    )
                }
            }
        } else {
            executablePath.withCString { path in
                posix_spawn(&childPID, path, &actions, &attributes, &arguments, environ)
            }
        }
        close(standardOutputPipe[1])
        close(standardErrorPipe[1])
        guard spawnStatus == 0 else {
            close(standardOutputPipe[0])
            close(standardErrorPipe[0])
            throw launchError(spawnStatus)
        }

        setNonBlocking(standardOutputPipe[0])
        setNonBlocking(standardErrorPipe[0])
        let outputSource = makeReadSource(descriptor: standardOutputPipe[0], stream: .standardOutput)
        let errorSource = makeReadSource(descriptor: standardErrorPipe[0], stream: .standardError)

        let alreadyFinished = lock.withLock { () -> Bool in
            processID = childPID
            standardOutputSource = outputSource
            standardErrorSource = errorSource
            return didFinish
        }
        outputSource.resume()
        errorSource.resume()

        let spawnedPID = childPID
        waitQueue.async { [weak self] in
            self?.waitForExit(processID: spawnedPID)
        }
        scheduleTimeoutIfNeeded()

        if alreadyFinished {
            terminate(processID: childPID)
            cancelReadSources()
        }
    }

    private func makePipe(_ descriptors: inout [Int32]) -> Int32 {
        descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.pipe(buffer.baseAddress!)
        }
    }

    private func closePair(_ descriptors: [Int32]) {
        descriptors.filter { $0 >= 0 }.forEach { close($0) }
    }

    private func setNonBlocking(_ descriptor: Int32) {
        let currentFlags = fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }
    }

    private func setCloseOnExec(_ descriptor: Int32) {
        let currentFlags = fcntl(descriptor, F_GETFD)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFD, currentFlags | FD_CLOEXEC)
        }
    }

    private func makeReadSource(descriptor: Int32, stream: Stream) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.drain(descriptor: descriptor, stream: stream)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        return source
    }

    private func drain(descriptor: Int32, stream: Stream) {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                consume(Data(bytes.prefix(count)), stream: stream)
            } else if count == 0 {
                return
            } else if errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    private func consume(_ data: Data, stream: Stream) {
        guard !data.isEmpty else { return }
        switch stream {
        case .standardOutput:
            standardOutput.append(data)
            let chunk = standardOutputDecoder.decode(data)
            if !chunk.isEmpty {
                onStandardOutput(chunk)
            }
        case .standardError:
            standardError.append(data)
            let chunk = standardErrorDecoder.decode(data)
            if !chunk.isEmpty {
                onStandardError(chunk)
            }
        }
    }

    private func waitForExit(processID: pid_t) {
        var status: Int32 = 0
        var waitedPID: pid_t
        repeat {
            waitedPID = waitpid(processID, &status, 0)
        } while waitedPID == -1 && errno == EINTR

        guard waitedPID == processID else {
            finish(
                .failure(ExternalProcessError.waitFailed(
                    executable: request.executableURL.lastPathComponent,
                    message: String(cString: strerror(errno))
                )),
                terminateRunningProcess: true
            )
            return
        }

        let waitStatus = status
        ioQueue.async { [weak self] in
            guard let self else { return }
            let sources = self.readSourceSnapshot()
            if let source = sources.output {
                self.drain(descriptor: Int32(source.handle), stream: .standardOutput)
            }
            if let source = sources.error {
                self.drain(descriptor: Int32(source.handle), stream: .standardError)
            }
            self.completeNormally(waitStatus: waitStatus)
        }
    }

    private func completeNormally(waitStatus: Int32) {
        let signal = waitStatus & 0x7f
        let termination: ExternalProcessTermination
        let exitCode: Int32
        if signal == 0 {
            exitCode = (waitStatus >> 8) & 0xff
            termination = .exited(code: exitCode)
        } else {
            exitCode = 128 + signal
            termination = .signaled(signal: signal)
        }
        let outputSnapshot = standardOutput.snapshot
        let errorSnapshot = standardError.snapshot
        // Normal EOF: emit any trailing bytes held across reads. The flush
        // decodes lossily, matching the byte-buffer snapshot above, so a split
        // scalar arrives whole and a trailing invalid sequence is surfaced the
        // same way in callbacks and in the final result.
        let outputFlush = standardOutputDecoder.flush()
        if !outputFlush.isEmpty {
            onStandardOutput(outputFlush)
        }
        let errorFlush = standardErrorDecoder.flush()
        if !errorFlush.isEmpty {
            onStandardError(errorFlush)
        }
        finish(
            .success(ExternalProcessResult(
                exitCode: exitCode,
                standardOutput: outputSnapshot.string,
                standardError: errorSnapshot.string,
                termination: termination,
                standardOutputWasTruncated: outputSnapshot.wasTruncated,
                standardErrorWasTruncated: errorSnapshot.wasTruncated
            )),
            terminateRunningProcess: false
        )
    }

    private func scheduleTimeoutIfNeeded() {
        guard let timeoutSeconds = request.timeoutSeconds else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(
                .failure(ExternalProcessError.timedOut(
                    executable: self.request.executableURL.lastPathComponent,
                    seconds: timeoutSeconds
                )),
                terminateRunningProcess: true
            )
        }
        let shouldSchedule = lock.withLock { () -> Bool in
            guard !didFinish else { return false }
            timeoutWorkItem = workItem
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, timeoutSeconds),
            execute: workItem
        )
    }

    private func finish(
        _ result: Result<ExternalProcessResult, any Error>,
        terminateRunningProcess: Bool
    ) {
        let state = lock.withLock { () -> (
            CheckedContinuation<ExternalProcessResult, any Error>?, pid_t?, DispatchWorkItem?, Bool
        ) in
            guard !didFinish else { return (nil, nil, nil, false) }
            didFinish = true
            completionResult = result
            let storedContinuation = continuation
            continuation = nil
            let timeout = timeoutWorkItem
            timeoutWorkItem = nil
            return (storedContinuation, processID, timeout, true)
        }
        guard state.3 else { return }
        state.2?.cancel()
        if terminateRunningProcess, let processID = state.1 {
            terminate(processID: processID)
        }
        cancelReadSources()
        if let continuation = state.0 {
            resume(continuation, with: result)
        }
    }

    private func resume(with result: Result<ExternalProcessResult, any Error>) {
        let storedContinuation = lock.withLock { () -> CheckedContinuation<ExternalProcessResult, any Error>? in
            let stored = continuation
            continuation = nil
            return stored
        }
        if let storedContinuation {
            resume(storedContinuation, with: result)
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<ExternalProcessResult, any Error>,
        with result: Result<ExternalProcessResult, any Error>
    ) {
        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func terminate(processID: pid_t) {
        signalProcessGroup(processID: processID, signal: SIGTERM)
        let grace = terminationGraceSeconds
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            self.signalProcessGroup(processID: processID, signal: SIGKILL)
        }
    }

    private func signalProcessGroup(processID: pid_t, signal: Int32) {
        if kill(-processID, signal) != 0, errno != ESRCH {
            _ = kill(processID, signal)
        }
    }

    private func readSourceSnapshot() -> (output: DispatchSourceRead?, error: DispatchSourceRead?) {
        lock.withLock {
            (output: standardOutputSource, error: standardErrorSource)
        }
    }

    private func cancelReadSources() {
        let sources = lock.withLock { () -> (DispatchSourceRead?, DispatchSourceRead?) in
            let output = standardOutputSource
            let error = standardErrorSource
            standardOutputSource = nil
            standardErrorSource = nil
            return (output, error)
        }
        sources.0?.cancel()
        sources.1?.cancel()
    }

    private func launchError(_ code: Int32) -> ExternalProcessError {
        ExternalProcessError.launchFailed(
            executable: request.executableURL.lastPathComponent,
            message: String(cString: strerror(code))
        )
    }
}

/// Incremental UTF-8 decoder for one captured pipe.
///
/// Arbitrary pipe reads can split a multibyte scalar across chunks, in which
/// case a per-chunk strict decode fails and the text would be silently
/// dropped from the streaming callbacks even though the accumulated bytes
/// decode. This decoder emits only complete characters promptly and in order:
/// each call delivers the newly completable prefix exactly once and retains
/// at most a 3-byte incomplete suffix (the longest possible truncated UTF-8
/// sequence) for the next read. `flush()` emits the held suffix lossily on
/// normal EOF, consistent with the lossy byte-buffer snapshot. Malformed bytes
/// are never held: only a trailing run that can still complete a scalar is
/// retained, so an invalid byte followed by valid ASCII is emitted promptly.
final class StreamingUTF8Decoder {
    private var pending = Data()

    func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var buffer = pending
        buffer.append(data)
        let tailLength = Self.incompleteTrailingLength(of: buffer)
        let emitLength = buffer.count - tailLength
        let text = String(decoding: buffer.prefix(emitLength), as: UTF8.self)
        pending = Data(buffer.suffix(tailLength))
        return text
    }

    func flush() -> String {
        guard !pending.isEmpty else { return "" }
        let remainder = pending
        pending = Data()
        return String(decoding: remainder, as: UTF8.self)
    }

    /// Length (0...3) of the trailing byte run that may still complete a
    /// scalar with future bytes. Only the trailing scalar shape is examined,
    /// so earlier malformed bytes never pin later valid text: they are emitted
    /// lossily on the next call or at flush. Invalid starters (C0, C1, F5-FF)
    /// and isolated continuations report 0. Restricted second bytes (E0
    /// requires A0-BF, ED requires 80-9F, F0 requires 90-BF, F4 requires
    /// 80-8F) are checked, so E0 80, ED A0, F0 80, and F4 90 report 0.
    private static func incompleteTrailingLength(of buffer: Data) -> Int {
        guard !buffer.isEmpty else { return 0 }
        let count = buffer.count
        let last = buffer[count - 1]
        // ASCII is always complete.
        if last < 0x80 {
            return 0
        }
        if last < 0xC0 {
            // Trailing continuation byte: find its starter within the last 4 bytes.
            var continuationCount = 0
            let window = min(4, count)
            for offset in 0..<window {
                let byte = buffer[count - 1 - offset]
                if byte >= 0x80, byte < 0xC0 {
                    continuationCount += 1
                } else {
                    break
                }
            }
            // No starter in the window (or longer than any scalar): isolated
            // continuations are malformed, emit them immediately.
            if continuationCount >= 4 || continuationCount >= count {
                return 0
            }
            let starter = buffer[count - continuationCount - 1]
            let expected: Int
            if starter >= 0xC2, starter <= 0xDF {
                expected = 1
            } else if starter >= 0xE0, starter <= 0xEF {
                expected = 2
            } else if starter >= 0xF0, starter <= 0xF4 {
                expected = 3
            } else {
                return 0
            }
            if continuationCount >= 1, !isValidSecondByte(
                starter: starter,
                second: buffer[count - continuationCount]
            ) {
                return 0
            }
            if continuationCount < expected {
                return continuationCount + 1
            }
            return 0
        }
        // Trailing lead byte: hold it for a future continuation. Invalid
        // starters are malformed and emitted immediately.
        if (last >= 0xC2 && last <= 0xDF)
            || (last >= 0xE0 && last <= 0xEF)
            || (last >= 0xF0 && last <= 0xF4) {
            return 1
        }
        return 0
    }

    private static func isValidSecondByte(starter: UInt8, second: UInt8) -> Bool {
        switch starter {
        case 0xE0:
            return second >= 0xA0 && second <= 0xBF
        case 0xED:
            return second >= 0x80 && second <= 0x9F
        case 0xF0:
            return second >= 0x90 && second <= 0xBF
        case 0xF4:
            return second >= 0x80 && second <= 0x8F
        default:
            return true
        }
    }
}

private final class BoundedProcessData: @unchecked Sendable {
    struct Snapshot {
        let string: String
        let wasTruncated: Bool
    }

    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var wasTruncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.withLock {
            if newData.count >= limit {
                data = newData.suffix(limit)
                wasTruncated = true
                return
            }
            let overflow = data.count + newData.count - limit
            if overflow > 0 {
                data.removeFirst(overflow)
                wasTruncated = true
            }
            data.append(newData)
        }
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                string: String(decoding: data, as: UTF8.self),
                wasTruncated: wasTruncated
            )
        }
    }
}
