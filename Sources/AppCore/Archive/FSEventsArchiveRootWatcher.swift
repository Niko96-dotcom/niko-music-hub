import CoreServices
import Foundation

/// Debounced FSEvents observer for archive root directories.
///
/// All stream and callback state is confined to `eventQueue`. The FSEvents
/// context uses an unretained pointer because the watcher owns the stream and
/// synchronously drains the queue before releasing it.
public final class FSEventsArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    typealias StreamStarter = (FSEventStreamRef) -> Bool

    /// FSEvents cannot provide a complete path-level delta for these cases.
    /// Treat all of them as one full-rescan request rather than mis-scoping a
    /// synthetic path (such as `/`) to an incremental scan.
    /// Volume mounts/unmounts and root renames are included: their paths say
    /// nothing about which song folders appeared or vanished.
    private static let fullRescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
    )

    private final class DeliveryToken: @unchecked Sendable {
        private let lock = NSLock()
        private var isActive = true

        func cancel() {
            lock.withLock { isActive = false }
        }

        @MainActor
        func performIfActive(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard isActive else { return }
            body()
        }
    }

    private let debounceInterval: TimeInterval
    private let eventQueue: DispatchQueue
    private let streamStarter: StreamStarter
    private let maximumPendingPathCount: Int
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueID = UUID()

    // eventQueue-confined state
    private var stream: FSEventStreamRef?
    private var streamStarted = false
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor (ArchiveRootWatchEvent) -> Void)?
    private var pendingChangedPaths: Set<String> = []
    /// Set once a batch outgrows `maximumPendingPathCount`: pending paths are then
    /// reduced to their song folder (or root-level entry) under a watched root.
    private var isCoalescingToSongFolders = false
    /// Each watched root as given and as resolved, since FSEvents reports real paths.
    private var rootPrefixes: [String] = []
    private var fullRescanRequired = false
    private var deliveryToken: DeliveryToken?
    private var isActive = false

    public convenience init(
        debounceInterval: TimeInterval = 2.0,
        eventQueue: DispatchQueue = DispatchQueue(label: "com.nikomusichub.archive.fsevents"),
        maximumPendingPathCount: Int = 1_024
    ) {
        self.init(
            debounceInterval: debounceInterval,
            eventQueue: eventQueue,
            streamStarter: { FSEventStreamStart($0) },
            maximumPendingPathCount: maximumPendingPathCount
        )
    }

    init(
        debounceInterval: TimeInterval,
        eventQueue: DispatchQueue,
        streamStarter: @escaping StreamStarter,
        maximumPendingPathCount: Int = 1_024
    ) {
        precondition(maximumPendingPathCount > 0, "maximumPendingPathCount must be positive")
        self.debounceInterval = debounceInterval
        self.eventQueue = eventQueue
        self.streamStarter = streamStarter
        self.maximumPendingPathCount = maximumPendingPathCount
        eventQueue.setSpecific(key: queueKey, value: queueID)
    }

    deinit {
        withEventQueueSync {
            stopLocked()
        }
    }

    public func setRoots(
        _ roots: [URL],
        onChange: @escaping @MainActor (ArchiveRootWatchEvent) -> Void
    ) -> Bool {
        withEventQueueSync {
            stopLocked()
            guard !roots.isEmpty else { return true }

            self.onChange = onChange
            rootPrefixes = Self.rootPrefixes(for: roots)
            isActive = true
            let token = DeliveryToken()
            deliveryToken = token
            let paths = roots.map(\.path) as CFArray
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
            )
            guard let createdStream = FSEventStreamCreate(
                nil,
                { _, info, numEvents, eventPaths, eventFlags, _ in
                    guard let info, numEvents > 0 else { return }
                    let watcher = Unmanaged<FSEventsArchiveRootWatcher>
                        .fromOpaque(info)
                        .takeUnretainedValue()
                    let array = unsafeBitCast(eventPaths, to: CFArray.self)
                    watcher.recordFSEventBatchLocked(
                        paths: array,
                        eventFlags: eventFlags,
                        count: numEvents
                    )
                },
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,
                flags
            ) else {
                stopLocked()
                return false
            }

            stream = createdStream
            FSEventStreamSetDispatchQueue(createdStream, eventQueue)
            guard streamStarter(createdStream) else {
                stopLocked()
                return false
            }
            streamStarted = true
            return true
        }
    }

    public func stop() {
        withEventQueueSync {
            stopLocked()
        }
    }

    /// Behavioral test hook that enters through the same queue-confined path
    /// as the FSEvents callback.
    func simulateChangedPaths(_ paths: [String]) {
        eventQueue.async { [weak self] in
            self?.recordChangedPathsLocked(paths)
        }
    }

    /// Behavioral test hook that exercises the event-flag overflow path before
    /// paths are decoded, as the native FSEvents callback does.
    func simulateFSEventBatch(
        paths: [String],
        eventFlags: [FSEventStreamEventFlags]
    ) {
        eventQueue.async { [weak self] in
            guard let self else { return }
            if paths.count > self.maximumDecodedBatchCount
                || eventFlags.contains(where: Self.requiresFullRescan) {
                self.recordFullRescanRequiredLocked()
            } else {
                self.recordChangedPathsLocked(paths)
            }
        }
    }

    private func stopLocked() {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        isActive = false
        deliveryToken?.cancel()
        deliveryToken = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChangedPaths.removeAll()
        isCoalescingToSongFolders = false
        rootPrefixes = []
        fullRescanRequired = false
        onChange = nil

        if let stream {
            if streamStarted {
                FSEventStreamStop(stream)
            }
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        streamStarted = false
    }

    private func recordChangedPathsLocked(_ paths: [String]) {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        guard isActive, !paths.isEmpty else { return }
        guard !fullRescanRequired else { return }
        for path in paths {
            guard appendChangedPathLocked(path) else { return }
        }
        scheduleDebouncedCallbackLocked()
    }

    /// Decodes only the bounded prefix required to detect an overflow. Do not
    /// materialize the whole FSEvents callback as `[String]`: a single native
    /// batch can contain an arbitrary number of paths during a filesystem storm.
    private func recordFSEventBatchLocked(
        paths: CFArray,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?,
        count: CFIndex
    ) {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        guard isActive, count > 0 else { return }
        // Paths are decoded one at a time and coalesced to song folders, so a
        // storm costs one string per event, never a materialized array. Past
        // this bound even that is not worth it: fall back before walking the
        // flags/paths of the callback.
        guard count <= maximumDecodedBatchCount else {
            recordFullRescanRequiredLocked()
            return
        }
        if Self.requiresFullRescan(eventFlags: eventFlags, count: count) {
            recordFullRescanRequiredLocked()
            return
        }
        guard !fullRescanRequired else { return }

        for index in 0..<count {
            guard let pointer = CFArrayGetValueAtIndex(paths, index) else { continue }
            let path = Unmanaged<CFString>
                .fromOpaque(pointer)
                .takeUnretainedValue() as String
            guard appendChangedPathLocked(path) else { return }
        }
        scheduleDebouncedCallbackLocked()
    }

    /// Returns `false` after replacing the bounded incremental batch with a
    /// full-rescan request, so callers stop decoding more paths immediately.
    ///
    /// Past `maximumPendingPathCount` exact paths, the batch keeps going as the
    /// set of song folders (and root-level entries) those paths live in — what
    /// the incremental scan rescans anyway. Only a path outside every watched
    /// root, or more distinct song folders than the budget, falls back to a
    /// full rescan.
    private func appendChangedPathLocked(_ path: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        if !isCoalescingToSongFolders {
            guard !pendingChangedPaths.contains(path) else { return true }
            if pendingChangedPaths.count < maximumPendingPathCount {
                pendingChangedPaths.insert(path)
                return true
            }
            isCoalescingToSongFolders = true
            let exactPaths = pendingChangedPaths
            pendingChangedPaths.removeAll(keepingCapacity: true)
            for exactPath in exactPaths {
                guard insertCoalescedPathLocked(exactPath) else { return false }
            }
        }
        return insertCoalescedPathLocked(path)
    }

    private func insertCoalescedPathLocked(_ path: String) -> Bool {
        guard let songFolderPath = Self.songFolderPath(containing: path, rootPrefixes: rootPrefixes) else {
            recordFullRescanRequiredLocked()
            return false
        }
        guard !pendingChangedPaths.contains(songFolderPath) else { return true }
        guard pendingChangedPaths.count < maximumPendingPathCount else {
            recordFullRescanRequiredLocked()
            return false
        }
        pendingChangedPaths.insert(songFolderPath)
        return true
    }

    /// The root itself, or the entry directly inside the deepest watched root
    /// that contains `path`, spelled with the same root prefix as `path`.
    /// `nil` when `path` is outside every root.
    static func songFolderPath(containing path: String, rootPrefixes: [String]) -> String? {
        guard let root = rootPrefixes
            .filter({ path == $0 || path.hasPrefix($0 + "/") })
            .max(by: { $0.count < $1.count }) else { return nil }
        guard path != root,
              let first = path.dropFirst(root.count + 1).split(separator: "/").first else { return root }
        return root + "/" + first
    }

    private static func rootPrefixes(for roots: [URL]) -> [String] {
        var prefixes: [String] = []
        for root in roots {
            for prefix in [root.standardizedFileURL.path, root.resolvingSymlinksInPath().standardizedFileURL.path]
            where !prefixes.contains(prefix) {
                prefixes.append(prefix)
            }
        }
        return prefixes
    }

    private var maximumDecodedBatchCount: Int {
        maximumPendingPathCount.multipliedReportingOverflow(by: 64).overflow
            ? Int.max
            : maximumPendingPathCount * 64
    }

    private func recordFullRescanRequiredLocked() {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        guard isActive else { return }
        pendingChangedPaths.removeAll(keepingCapacity: true)
        isCoalescingToSongFolders = false
        guard !fullRescanRequired else { return }
        fullRescanRequired = true
        scheduleDebouncedCallbackLocked()
    }

    private func scheduleDebouncedCallbackLocked() {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        // Keep one fixed coalescing window per batch. Replacing a delayed work
        // item for every event leaves cancelled items queued until their
        // deadlines and can itself become an unbounded storm allocation.
        guard debounceWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isActive,
                  let onChange = self.onChange,
                  let token = self.deliveryToken else { return }
            let event: ArchiveRootWatchEvent
            if self.fullRescanRequired {
                self.fullRescanRequired = false
                event = .fullRescanRequired
            } else {
                let paths = self.pendingChangedPaths
                    .sorted()
                    .map { URL(fileURLWithPath: $0) }
                self.pendingChangedPaths.removeAll(keepingCapacity: true)
                self.isCoalescingToSongFolders = false
                guard !paths.isEmpty else { return }
                event = .paths(paths)
            }
            self.debounceWorkItem = nil
            Task { @MainActor in
                token.performIfActive {
                    onChange(event)
                }
            }
        }
        debounceWorkItem = work
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private static func requiresFullRescan(_ flags: FSEventStreamEventFlags) -> Bool {
        (flags & fullRescanFlags) != 0
    }

    private static func requiresFullRescan(
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?,
        count: CFIndex
    ) -> Bool {
        guard let eventFlags else { return false }
        return (0..<count).contains { index in
            requiresFullRescan(eventFlags[index])
        }
    }

    private func withEventQueueSync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueID {
            return try body()
        }
        return try eventQueue.sync(execute: body)
    }
}
