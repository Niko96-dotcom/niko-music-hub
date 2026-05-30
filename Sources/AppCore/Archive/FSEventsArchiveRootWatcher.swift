import CoreServices
import Foundation

/// Debounced FSEvents observer for archive root directories.
public final class FSEventsArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    private let debounceInterval: TimeInterval
    private let eventQueue: DispatchQueue
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor () -> Void)?

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

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor () -> Void) {
        stop()
        self.onChange = onChange
        guard !roots.isEmpty else { return }

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
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FSEventsArchiveRootWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleDebouncedCallback()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        onChange = nil
    }

    private func scheduleDebouncedCallback() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            Task { @MainActor in
                onChange()
            }
        }
        debounceWorkItem = work
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
