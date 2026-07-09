import CoreServices
import Foundation
import os

/// Debounced FSEvents observer for archive root directories.
public final class FSEventsArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    private let debounceInterval: TimeInterval
    private let eventQueue: DispatchQueue
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor ([URL]) -> Void)?
    private var pendingChangedPaths: Set<String> = []
    private let pathsLock = NSLock()
    private let stoppedLock = OSAllocatedUnfairLock(initialState: false)

    private var isStopped: Bool {
        stoppedLock.withLock { $0 }
    }

    public init(
        debounceInterval: TimeInterval = 2.0,
        eventQueue: DispatchQueue = DispatchQueue(label: "com.nikomusichub.archive.fsevents")
    ) {
        self.debounceInterval = debounceInterval
        self.eventQueue = eventQueue
    }

    deinit {
        stop()
    }

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) -> Bool {
        stop()
        self.onChange = onChange
        pathsLock.lock()
        pendingChangedPaths.removeAll()
        pathsLock.unlock()
        guard !roots.isEmpty else { return true }

        stoppedLock.withLock { $0 = false }
        let paths = roots.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: { pointer in
                if let pointer {
                    _ = Unmanaged<FSEventsArchiveRootWatcher>.fromOpaque(pointer).retain()
                }
                return pointer
            },
            release: { pointer in
                if let pointer {
                    Unmanaged<FSEventsArchiveRootWatcher>.fromOpaque(pointer).release()
                }
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info, numEvents > 0 else { return }
                let watcher = Unmanaged<FSEventsArchiveRootWatcher>.fromOpaque(info).takeUnretainedValue()
                guard !watcher.isStopped else { return }
                let array = unsafeBitCast(eventPaths, to: CFArray.self)
                let paths = (0..<numEvents).compactMap { index -> String? in
                    let pointer = CFArrayGetValueAtIndex(array, index)
                    guard let pointer else { return nil }
                    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
                }
                watcher.recordChangedPaths(paths)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            Unmanaged<FSEventsArchiveRootWatcher>.fromOpaque(context.info!).release()
            self.onChange = nil
            return false
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        FSEventStreamStart(stream)
        return true
    }

    public func stop() {
        stoppedLock.withLock { $0 = true }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        onChange = nil
        pathsLock.lock()
        pendingChangedPaths.removeAll()
        pathsLock.unlock()
    }

    private func recordChangedPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        pathsLock.lock()
        pendingChangedPaths.formUnion(paths)
        pathsLock.unlock()
        scheduleDebouncedCallback()
    }

    private func scheduleDebouncedCallback() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            self.pathsLock.lock()
            let paths = self.pendingChangedPaths.map { URL(fileURLWithPath: $0) }
            self.pendingChangedPaths.removeAll()
            self.pathsLock.unlock()
            guard !paths.isEmpty else { return }
            Task { @MainActor in
                onChange(paths)
            }
        }
        debounceWorkItem = work
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
