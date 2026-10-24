import Foundation
import SwiftUI

public struct ToolFeatureID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public var description: String {
        rawValue
    }
}

/// Where a tool sits in the sidebar. The Tools menu, the Dock menu, ⌘1…⌘9 and the
/// sidebar's arrow keys follow the same order (`sidebarOrder`).
public enum ToolSection: CaseIterable, Sendable, Codable, Hashable {
    /// Under "Library", first.
    case library
    /// Under "Production", in registration order.
    case production
    /// The bottom row. Selecting it opens the Settings window, so it is never the
    /// main pane or the launch tool and has no ⌘ digit.
    case settings

    /// Sidebar order: each section in turn, tools in registration order.
    public static func sidebarOrder(_ metadata: [ToolMetadata]) -> [ToolMetadata] {
        allCases.flatMap { section in metadata.filter { $0.section == section } }
    }
}

public struct ToolMetadata: Hashable, Codable, Sendable {
    public let id: ToolFeatureID
    public let displayName: String
    public let shortLabel: String
    public let systemImage: String
    public let section: ToolSection

    public init(
        id: ToolFeatureID,
        displayName: String,
        shortLabel: String,
        systemImage: String,
        section: ToolSection = .production
    ) {
        self.id = id
        self.displayName = displayName
        self.shortLabel = shortLabel
        self.systemImage = systemImage
        self.section = section
    }
}

public protocol ToolFeature: Sendable {
    var metadata: ToolMetadata { get }

    @MainActor
    func makeView(context: ToolContext) -> AnyView

    /// Optional control the shell shows in the window title bar (next to the
    /// panel toggles) while this tool is active. Default: none.
    @MainActor
    func makeTitleBarAccessory(context: ToolContext) -> AnyView?
}

public extension ToolFeature {
    @MainActor
    func makeTitleBarAccessory(context _: ToolContext) -> AnyView? { nil }
}
