import Combine
import Foundation

/// Observable mirror of the persisted `AppSettings`.
///
/// `SettingsStore` is load/save only; views that showed a setting used to
/// snapshot it in `onAppear`, which runs once for cached tool panes, so a
/// change made in Settings never reached an already-mounted tool. This object
/// is the single observable source: it loads once and follows the store's
/// change stream on the main thread.
public final class AppSettingsObserver: ObservableObject, @unchecked Sendable {
    @Published public private(set) var settings: AppSettings

    private var subscription: AnyCancellable?

    public init(store: any SettingsStore) {
        settings = (try? store.loadSettings()) ?? .default
        subscription = store.settingsChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self, settings != self.settings else { return }
                self.settings = settings
            }
    }
}
