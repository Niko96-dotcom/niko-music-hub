import Foundation

/// Order-preserving parallel map for independent, pure per-element work over a large array: decoding
/// or classifying every song of a 10,000-song archive. The result equals `input.map(transform)`; only
/// the wall time changes. Small inputs and single-core machines run on the calling thread.
///
/// `transform` runs on several threads at once. It is `@Sendable` and the elements are `Sendable`, so the
/// compiler checks that it touches no unsynchronized shared state.
/// Threads claim the next elements as they finish, so songs of very different size balance out. The
/// first failure (lowest index) is rethrown after the running threads stop.
///
/// More threads is not always faster: Foundation's JSON and string work contends on runtime metadata
/// locks, and many threads opening files at once make the kernel spend more time contending than
/// reading. `maximumThreads` is therefore a per-call budget, not "all cores".
enum ParallelMap {
    static let defaultMinimumParallelCount = 64
    static let defaultMaximumThreads = 8

    static func map<Input: Sendable, Output: Sendable>(
        _ input: [Input],
        minimumParallelCount: Int = defaultMinimumParallelCount,
        maximumThreads: Int = defaultMaximumThreads,
        _ transform: @Sendable (Input) throws -> Output
    ) throws -> [Output] {
        let threads = min(ProcessInfo.processInfo.activeProcessorCount, maximumThreads, input.count)
        guard threads > 1, input.count >= max(2, minimumParallelCount) else {
            return try input.map(transform)
        }
        let slots = UnsafeMutablePointer<Output?>.allocate(capacity: input.count)
        slots.initialize(repeating: nil, count: input.count)
        defer {
            slots.deinitialize(count: input.count)
            slots.deallocate()
        }
        let failure = FirstFailure()
        withoutActuallyEscaping(transform) { transform in
            let job = Job(input: input, slots: slots, transform: transform, failure: failure, cursor: Cursor())
            DispatchQueue.concurrentPerform(iterations: threads) { _ in
                job.run()
            }
        }
        if let error = failure.error { throw error }
        var output: [Output] = []
        output.reserveCapacity(input.count)
        for index in 0..<input.count {
            guard let value = slots[index] else { preconditionFailure("ParallelMap left slot \(index) empty") }
            output.append(value)
        }
        return output
    }

    /// Non-throwing convenience.
    static func map<Input: Sendable, Output: Sendable>(
        _ input: [Input],
        minimumParallelCount: Int = defaultMinimumParallelCount,
        maximumThreads: Int = defaultMaximumThreads,
        _ transform: @Sendable (Input) -> Output
    ) -> [Output] {
        do {
            return try map(input, minimumParallelCount: minimumParallelCount, maximumThreads: maximumThreads) {
                (element: Input) throws -> Output in
                transform(element)
            }
        } catch {
            preconditionFailure("A non-throwing ParallelMap transform threw \(error)")
        }
    }
}

/// One `map` call's shared state. `@unchecked` only because of `slots`: threads write disjoint slots
/// and only read `input`; `input`, `transform` and `Output` are checked `Sendable`.
private struct Job<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    let input: [Input]
    let slots: UnsafeMutablePointer<Output?>
    let transform: @Sendable (Input) throws -> Output
    let failure: FirstFailure
    let cursor: Cursor

    func run() {
        while let index = cursor.next(limit: input.count) {
            if failure.hasFailed(before: index) { return }
            // Each element may autorelease Foundation objects (JSON, regular expressions, file URLs).
            do {
                try autoreleasepool { slots[index] = try transform(input[index]) }
            } catch {
                failure.record(error, at: index)
                return
            }
        }
    }
}

/// Hands out element indexes in increasing order, one at a time.
private final class Cursor: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next(limit: Int) -> Int? {
        lock.withLock {
            guard value < limit else { return nil }
            defer { value += 1 }
            return value
        }
    }
}

private final class FirstFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var lowest: (index: Int, error: Error)?

    var error: Error? { lock.withLock { lowest?.error } }

    /// A thread only needs to stop for a failure at a lower index than the one it is about to run.
    func hasFailed(before index: Int) -> Bool {
        lock.withLock { lowest.map { $0.index < index } ?? false }
    }

    func record(_ error: Error, at index: Int) {
        lock.withLock {
            if let current = lowest, current.index <= index { return }
            lowest = (index, error)
        }
    }
}
