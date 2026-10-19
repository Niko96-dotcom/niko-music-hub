import Foundation

/// Order-preserving parallel map for independent, pure per-element work over a large array: decoding
/// or classifying every song of a 10,000-song archive. The result equals `input.map(transform)`; only
/// the wall time changes. Small inputs and single-core machines run on the calling thread.
///
/// `transform` runs on several threads at once, so it must not touch unsynchronized shared state.
/// The first failure (lowest index) is rethrown after the running chunks stop.
enum ParallelMap {
    static let defaultMinimumParallelCount = 64

    static func map<Input, Output>(
        _ input: [Input],
        minimumParallelCount: Int = defaultMinimumParallelCount,
        _ transform: (Input) throws -> Output
    ) throws -> [Output] {
        let workers = ProcessInfo.processInfo.activeProcessorCount
        guard workers > 1, input.count >= max(2, minimumParallelCount) else {
            return try input.map(transform)
        }
        // More chunks than workers evens out songs of very different size.
        let chunkCount = min(input.count, workers * 4)
        let slots = UnsafeMutablePointer<Output?>.allocate(capacity: input.count)
        slots.initialize(repeating: nil, count: input.count)
        defer {
            slots.deinitialize(count: input.count)
            slots.deallocate()
        }
        let failure = FirstFailure()
        withoutActuallyEscaping(transform) { transform in
            let job = Job(
                input: input, slots: slots, transform: transform, failure: failure,
                chunkSize: (input.count + chunkCount - 1) / chunkCount
            )
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                job.run(chunk: chunk)
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
    static func map<Input, Output>(
        _ input: [Input],
        minimumParallelCount: Int = defaultMinimumParallelCount,
        _ transform: (Input) -> Output
    ) -> [Output] {
        do {
            return try map(input, minimumParallelCount: minimumParallelCount) { (element: Input) throws -> Output in
                transform(element)
            }
        } catch {
            preconditionFailure("A non-throwing ParallelMap transform threw \(error)")
        }
    }
}

/// One `map` call's shared state. Chunks write disjoint slots of `slots` and only read `input`, so
/// sharing it across the worker threads is safe; `transform` is the caller's contract (see above).
private struct Job<Input, Output>: @unchecked Sendable {
    let input: [Input]
    let slots: UnsafeMutablePointer<Output?>
    let transform: (Input) throws -> Output
    let failure: FirstFailure
    let chunkSize: Int

    func run(chunk: Int) {
        let start = chunk * chunkSize
        let end = min(input.count, start + chunkSize)
        guard start < end else { return }
        for index in start..<end {
            if failure.hasFailed(before: index) { return }
            // Each element may autorelease Foundation objects (JSON, regular expressions).
            do {
                try autoreleasepool { slots[index] = try transform(input[index]) }
            } catch {
                failure.record(error, at: index)
                return
            }
        }
    }
}

private final class FirstFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var lowest: (index: Int, error: Error)?

    var error: Error? { lock.withLock { lowest?.error } }

    /// Chunks only need to stop for a failure at a lower index than the one they are about to run.
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
