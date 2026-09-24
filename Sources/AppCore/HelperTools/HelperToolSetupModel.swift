import Combine
import Foundation

/// One-click helper-tool "Set Up" state (STATE + ROUTING layer only; views come later).
///
/// Owned by the app composition (`AppComposition.helperSetup`) so installs continue
/// if the sheet closes. The sheet itself is owned by `HubShellSession.isSetupPresented`.
@MainActor
public final class HelperToolSetupModel: ObservableObject, @unchecked Sendable {
    public enum BundleState: Equatable {
        case checking
        case notInstalled
        case installed
        case installing(HelperInstallProgress)
        case failed(String)
    }

    @Published public private(set) var states: [HelperToolBundle: BundleState] = [
        .downloadAndConvert: .checking,
        .stemSeparation: .checking,
    ]
    /// Increments after every successful install; feature views may observe it later.
    @Published public private(set) var installGeneration: Int = 0

    private let locator: HelperToolLocator
    private let installer: HelperToolInstaller
    private let settingsProvider: @MainActor () -> HelperToolSettings
    private var installTask: Task<Void, Never>?
    /// Identifies the run that owns `installTask`. A run cancelled by
    /// `cancelInstalls()` still finishes its Task later; without the check its
    /// completion would nil out the task of an install started after the cancel
    /// and let a second install run concurrently.
    private var installRunID: UInt64 = 0

    public init(
        locator: HelperToolLocator = .standard(),
        installer: HelperToolInstaller? = nil,
        settingsProvider: @escaping @MainActor () -> HelperToolSettings
    ) {
        self.locator = locator
        self.installer = installer ?? HelperToolInstaller(locator: locator)
        self.settingsProvider = settingsProvider
    }

    /// Synchronous file checks only. Bundles currently installing keep their progress.
    public func refresh() {
        let settings = settingsProvider()
        for bundle in HelperToolBundle.allCases {
            if case .installing = states[bundle] { continue }
            let resolved = bundle.tools.allSatisfy { locator.resolve($0, settings: settings) != nil }
            states[bundle] = resolved ? .installed : .notInstalled
        }
    }

    /// One install runs at a time; the sheet disables its buttons meanwhile, so a
    /// second request while one is running is ignored rather than queued.
    public func install(_ bundle: HelperToolBundle) {
        guard installTask == nil else { return }
        states[bundle] = .installing(HelperInstallProgress(phase: "Starting", fractionCompleted: nil))
        let runID = beginInstallRun()
        installTask = Task { [weak self] in
            await self?.performInstall(bundle, runID: runID)
            self?.finishInstallRun(runID)
        }
    }

    /// Installs every bundle whose state is `.notInstalled` or `.failed`,
    /// sequentially, Download & Convert first, in ONE Task.
    public func installMissing() {
        guard installTask == nil else { return }
        let runID = beginInstallRun()
        installTask = Task { [weak self] in
            await self?.performInstallMissing(runID: runID)
            self?.finishInstallRun(runID)
        }
    }

    /// The cancelled run keeps its id until a new install starts, so its own
    /// cancellation reset (row back to Not Installed) still lands when nothing
    /// replaced it, while a run started after the cancel is left alone.
    public func cancelInstalls() {
        installTask?.cancel()
        installTask = nil
    }

    private func beginInstallRun() -> UInt64 {
        installRunID &+= 1
        return installRunID
    }

    private func finishInstallRun(_ runID: UInt64) {
        guard installRunID == runID else { return }
        installTask = nil
    }

    public var isInstalling: Bool {
        states.values.contains {
            if case .installing = $0 { return true }
            return false
        }
    }

    public var allInstalled: Bool {
        HelperToolBundle.allCases.allSatisfy { states[$0] == .installed }
    }

    private func performInstallMissing(runID: UInt64) async {
        for bundle in [HelperToolBundle.downloadAndConvert, HelperToolBundle.stemSeparation] {
            if Task.isCancelled { break }
            let current = states[bundle] ?? .checking
            switch current {
            case .notInstalled, .failed:
                break
            case .checking, .installed, .installing:
                continue
            }
            await performInstall(bundle, runID: runID)
        }
    }

    private func performInstall(_ bundle: HelperToolBundle, runID: UInt64) async {
        if case .installing = states[bundle] {
            // Already tracked (set synchronously by install(_:)).
        } else {
            states[bundle] = .installing(HelperInstallProgress(phase: "Starting", fractionCompleted: nil))
        }
        do {
            try await installer.install(bundle) { [weak self] value in
                Task { @MainActor [weak self] in
                    // Progress hops can land after the install finished; never
                    // turn a finished or failed row back into "installing".
                    guard let self, case .installing = self.states[bundle] else { return }
                    self.states[bundle] = .installing(value)
                }
            }
            try Task.checkCancellation()
            // refresh() skips rows that are installing, so clear this one first.
            states[bundle] = .checking
            refresh()
            installGeneration += 1
        } catch is CancellationError {
            // A run cancelled and replaced by a newer install must not reset the
            // row the newer run is now driving.
            guard installRunID == runID else { return }
            states[bundle] = .checking
            refresh()
        } catch {
            guard installRunID == runID else { return }
            states[bundle] = .failed(error.localizedDescription)
        }
    }
}
