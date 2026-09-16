import AppKit
import Foundation
import SwiftUI

public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case followSystem
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .followSystem:
            return "Follow System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    /// Tooltip help for the Appearance chips (NMH-068). Light/Dark pin the app
    /// appearance and override the system setting until Follow System is chosen.
    public var help: String? {
        switch self {
        case .followSystem:
            return nil
        case .light, .dark:
            return "Overrides the system appearance until you choose Follow System."
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .followSystem:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// AppKit appearance name for `NSApp.appearance`; `nil` follows the system.
    public var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .followSystem:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}
