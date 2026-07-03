import AppCore
import SwiftUI

@MainActor
final class AppAppearanceController: ObservableObject {
    @Published private(set) var appearance: AppAppearance

    init(appearance: AppAppearance = .followSystem) {
        self.appearance = appearance
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .followSystem:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func apply(_ appearance: AppAppearance) {
        self.appearance = appearance
    }
}
