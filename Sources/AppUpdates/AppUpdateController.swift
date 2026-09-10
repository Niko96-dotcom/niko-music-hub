import Foundation
@preconcurrency import Sparkle

/// Owns the Sparkle updater and mirrors its session into `AppUpdateStatus`.
///
/// Fail-closed by construction: when `AppUpdateConfiguration` refuses the
/// bundle, no `SPUStandardUpdaterController` is created at all, so a build that
/// lost its feed URL or signing key cannot fall back to an unverified update
/// path. It reports `.unavailable` and stays there.
@MainActor
public final class AppUpdateController: NSObject, ObservableObject {
    @Published public private(set) var status: AppUpdateStatus
    /// Mirrors `SPUUpdater.canCheckForUpdates`, which is false while a session runs.
    @Published public private(set) var canCheckForUpdates: Bool

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    /// Version string of the update the current session is working on. Cleared
    /// at the end of every cycle so a finished install cannot leave a stale
    /// "update available" banner behind.
    private var sessionVersion: String?

    public convenience override init() {
        self.init(configuration: AppUpdateConfiguration.resolve())
    }

    /// - Parameter suppressedReason: When non-nil the updater is switched off
    ///   before Sparkle is ever constructed, whatever the bundle says. Used to
    ///   keep automated end-to-end runs from contacting the feed or staging an
    ///   install against the very bundle under test.
    public init(
        configuration: Result<AppUpdateConfiguration, AppUpdateConfigurationError>,
        suppressedReason: String? = nil
    ) {
        if let suppressedReason {
            status = .unavailable(reason: suppressedReason)
            canCheckForUpdates = false
            super.init()
            return
        }

        switch configuration {
        case .failure(let error):
            status = .unavailable(reason: error.message)
            canCheckForUpdates = false
            super.init()
        case .success:
            status = .idle
            canCheckForUpdates = false
            super.init()
            // SPUUpdater takes its delegate at construction, so the controller
            // cannot exist until after super.init(). Sparkle reads SUFeedURL and
            // SUPublicEDKey from the host bundle itself; the resolved
            // configuration is the gate on getting this far, not a parameter.
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            self.controller = controller
            controller.startUpdater()
            canCheckForUpdates = controller.updater.canCheckForUpdates
            // SPUUpdater is main-thread-confined, so this fires from the main
            // thread; assumeIsolated traps loudly rather than racing if that
            // ever stops being true.
            canCheckObservation = controller.updater.observe(
                \.canCheckForUpdates,
                options: [.new]
            ) { [weak self] _, change in
                guard let value = change.newValue else { return }
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = value
                }
            }
        }
    }

    /// Whether Sparkle polls the feed on its own schedule.
    ///
    /// Backed by Sparkle's own defaults, so the toggle survives relaunches
    /// without this app keeping a duplicate copy of the setting.
    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let controller else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    public var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    /// A user-initiated check. Refuses to stack a second session on the first.
    public func checkForUpdates() {
        guard let controller else { return }
        guard controller.updater.canCheckForUpdates, !status.isBusy else { return }
        status = .checking
        controller.updater.checkForUpdates()
    }

    private func finishCycle(error: Error?) {
        sessionVersion = nil

        guard let error = error as NSError? else {
            status = .upToDate(checkedAt: lastUpdateCheckDate ?? Date())
            return
        }

        // "Nothing newer in the feed" arrives as an error. It is the healthy
        // outcome of a successful check and must never render as a failure.
        if error.domain == SUSparkleErrorDomain, error.code == SUError.noUpdateError.rawValue {
            status = .upToDate(checkedAt: lastUpdateCheckDate ?? Date())
            return
        }

        // A session that reached a staged install ends its cycle with a
        // cancellation-shaped error; keep the relaunch prompt in that case.
        if case .readyToRelaunch = status { return }

        status = .failed(message: error.localizedDescription)
    }
}

extension AppUpdateController: SPUUpdaterDelegate {
    public nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            sessionVersion = version
            status = .updateAvailable(version: version)
        }
    }

    public nonisolated func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            sessionVersion = version
            status = .downloading(version: version)
        }
    }

    public nonisolated func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            status = .extracting(version: version)
        }
    }

    public nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            status = .readyToRelaunch(version: version)
        }
    }

    public nonisolated func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: Error
    ) {
        let message = (error as NSError).localizedDescription
        MainActor.assumeIsolated {
            status = .failed(message: message)
        }
    }

    public nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            finishCycle(error: error)
        }
    }
}
