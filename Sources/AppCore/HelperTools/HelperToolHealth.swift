import Combine
import Foundation

/// What each helper can do now, for every tool and the shell. One instance per
/// app (`AppComposition`), carried by `ToolContext.helperHealth`.
///
/// A helper is probed the first time a surface asks for it (`check`), never at
/// launch: demucs-mlx can take up to 30 s to answer. After that it is probed
/// again when its saved path changes (followed through `appSettings`) and when
/// an install finishes (`helpersChanged()`, called by the Set Up model). A
/// status stays as it was until the new probe answers, so surfaces do not
/// flash back to "checking".
///
/// Main thread only, like `AppSettingsObserver`: the mutating calls are
/// `@MainActor`, and the init is plain so `ToolContext` can build its default.
public final class HelperToolHealth: ObservableObject, @unchecked Sendable {
    /// The last answer per helper; no entry until a surface asked for it.
    @Published public private(set) var statuses: [HelperTool: HelperToolStatus] = [:]
    /// Run-time gates (a download, the Converter's FFmpeg fallback) probe again
    /// with it, so they never act on an old status.
    public let probe: HelperToolProbe
    public var locator: HelperToolLocator { probe.locator }

    private let appSettings: AppSettingsObserver
    /// Helpers some surface asked for; only these are probed again after a change.
    private var askedFor: Set<HelperTool> = []
    /// Bumped per probe start, so an older probe that answers late is dropped.
    private var probeGenerations: [HelperTool: UInt64] = [:]
    private var running: [HelperTool: Task<HelperToolStatus, Never>] = [:]
    private var helperSettingsSubscription: AnyCancellable?

    public init(probe: HelperToolProbe, appSettings: AppSettingsObserver) {
        self.probe = probe
        self.appSettings = appSettings
        // `@Published` emits before the observer stores the value; one main-queue
        // turn later `appSettings.settings` holds the new paths the probe reads.
        helperSettingsSubscription = appSettings.$settings
            .map(\.helperTools)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.helpersChanged() }
            }
    }

    /// Probes `tool` unless an answer exists or a probe is running. Surfaces
    /// call it when they appear; the answer arrives through `statuses`.
    @MainActor
    public func check(_ tool: HelperTool) {
        askedFor.insert(tool)
        guard statuses[tool] == nil, running[tool] == nil else { return }
        startProbe(tool)
    }

    /// Probes `tool` now and returns the answer (Try Again, the strip opening).
    @MainActor
    @discardableResult
    public func recheck(_ tool: HelperTool) async -> HelperToolStatus {
        askedFor.insert(tool)
        return await startProbe(tool).value
    }

    /// Helpers changed on disk or in settings: probe again every helper a
    /// surface asked for.
    @MainActor
    public func helpersChanged() {
        for tool in askedFor {
            startProbe(tool)
        }
    }

    @MainActor
    @discardableResult
    private func startProbe(_ tool: HelperTool) -> Task<HelperToolStatus, Never> {
        let generation = (probeGenerations[tool] ?? 0) &+ 1
        probeGenerations[tool] = generation
        let probe = probe
        let settings = appSettings.settings.helperTools
        let task = Task { @MainActor [weak self] in
            let status = await probe.status(of: tool, settings: settings)
            self?.finishProbe(tool, status: status, generation: generation)
            return status
        }
        running[tool] = task
        return task
    }

    @MainActor
    private func finishProbe(_ tool: HelperTool, status: HelperToolStatus, generation: UInt64) {
        guard probeGenerations[tool] == generation else { return }
        running[tool] = nil
        if statuses[tool] != status {
            statuses[tool] = status
        }
    }
}
