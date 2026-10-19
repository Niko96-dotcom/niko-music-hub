import Foundation

extension Array where Element: Equatable & Sendable {
    /// The answer `self == other` gives, computed on several threads for large arrays.
    ///
    /// The archive compares its whole 10,000-song catalog against the previous one to decide whether to
    /// republish. When nothing changed (the usual rescan) every song is compared field by field,
    /// ~150 ms on the main thread per comparison; a launch makes several. A mismatch stops the
    /// remaining threads early; arrays that share storage are equal without comparing elements, as
    /// `Array.==` itself does.
    public func equalsConcurrently(_ other: [Element], minimumParallelCount: Int = 512) -> Bool {
        guard count == other.count else { return false }
        if isEmpty { return true }
        let sharesStorage = withUnsafeBufferPointer { lhs in
            other.withUnsafeBufferPointer { rhs in lhs.baseAddress == rhs.baseAddress }
        }
        if sharesStorage { return true }
        let threads = Swift.min(ProcessInfo.processInfo.activeProcessorCount, 8)
        guard threads > 1, count >= minimumParallelCount else { return self == other }
        let mismatch = MismatchFlag()
        let sliceLength = (count + threads - 1) / threads
        DispatchQueue.concurrentPerform(iterations: threads) { slice in
            var index = slice * sliceLength
            let end = Swift.min(count, index + sliceLength)
            while index < end {
                if mismatch.isSet { return }
                if self[index] != other[index] {
                    mismatch.set()
                    return
                }
                index += 1
            }
        }
        return !mismatch.isSet
    }
}

private final class MismatchFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}
