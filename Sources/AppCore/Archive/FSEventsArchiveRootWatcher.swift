import CoreServices
import Foundation

/// Debounced FSEvents observer for archive root directories.
///
/// All stream and callback state is confined to `eventQueue`. The FSEvents
/// context uses an unretained pointer because the watcher owns the stream and
/// synchronously drains the queue before releasing it.
public final class FSEventsArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    typealias StreamStarter = (FSEventStreamRef) -> Bool

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
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueID = UUID()

    // eventQueue-confined state
    private var stream: FSEventStreamRef?
    private var streamStarted = false
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor ([URL]) -> Void)?
    private var pendingChangedPaths: Set<String> = []
    private var deliveryToken: DeliveryToken?
    private var isActive = false

    public convenience init(
        debounceInterval: TimeInterval = 2.0,
        eventQueue: DispatchQueue = DispatchQueue(label: "com.nikomusichub.archive.fsevents")
    ) {
        self.init(
            debounceInterval: debounceInterval,
            eventQueue: eventQueue,
            streamStarter: { FSEventStreamStart($0) }
        )
    }

    init(
        debounceInterval: TimeInterval,
        eventQueue: DispatchQueue,
        streamStarter: @escaping StreamStarter
    ) {
        self.debounceInterval = debounceInterval
        self.eventQueue = eventQueue
        self.streamStarter = streamStarter
        eventQueue.setSpecific(key: queueKey, value: queueID)
    }

    deinit {
        withEventQueueSync {
            stopLocked()
        }
    }

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) -> Bool {
        withEventQueueSync {
            stopLocked()
            guard !roots.isEmpty else { return true }

            self.onChange = onChange
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
                { _, info, numEvents, eventPaths, _, _ in
                    guard let info, numEvents > 0 else { return }
                    let watcher = Unmanaged<FSEventsArchiveRootWatcher>
                        .fromOpaque(info)
                        .takeUnretainedValue()
                    let array = unsafeBitCast(eventPaths, to: CFArray.self)
                    let paths = (0..<numEvents).compactMap { index -> String? in
                        let pointer = CFArrayGetValueAtIndex(array, index)
                        guard let pointer else { return nil }
                        return Unmanaged<CFString>
                            .fromOpaque(pointer)
                            .takeUnretainedValue() as String
                    }
                    watcher.recordChangedPathsLocked(paths)
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

    private func stopLocked() {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        isActive = false
        deliveryToken?.cancel()
        deliveryToken = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChangedPaths.removeAll()
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
        pendingChangedPaths.formUnion(paths)
        scheduleDebouncedCallbackLocked()
    }

    private func scheduleDebouncedCallbackLocked() {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isActive,
                  let onChange = self.onChange,
                  let token = self.deliveryToken else { return }
            let paths = self.pendingChangedPaths
                .sorted()
                .map { URL(fileURLWithPath: $0) }
            self.pendingChangedPaths.removeAll()
            guard !paths.isEmpty else { return }
            Task { @MainActor in
                token.performIfActive {
                    onChange(paths)
                }
            }
        }
        debounceWorkItem = work
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func withEventQueueSync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueID {
            return try body()
        }
        return try eventQueue.sync(execute: body)
    }
}
