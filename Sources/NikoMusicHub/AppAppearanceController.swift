import AppCore
import AppKit
import SwiftUI

@MainActor
final class AppAppearanceController: ObservableObject {
    @Published private(set) var appearance: AppAppearance

    init(appearance: AppAppearance = .followSystem) {
        self.appearance = appearance
        applySystemAppearance(appearance)
    }

    var preferredColorScheme: ColorScheme? {
        appearance.preferredColorScheme
    }

    func apply(_ appearance: AppAppearance) {
        self.appearance = appearance
        applySystemAppearance(appearance)
    }

    private func applySystemAppearance(_ appearance: AppAppearance) {
        DispatchQueue.main.async {
            if let name = appearance.nsAppearanceName {
                NSApp.appearance = NSAppearance(named: name)
            } else {
                NSApp.appearance = nil
            }
        }
    }
}
