import Foundation

public struct DuplicateToolFeatureID: Error, Equatable, Sendable, CustomStringConvertible {
    public let id: ToolFeatureID

    public init(id: ToolFeatureID) {
        self.id = id
    }

    public var description: String {
        "Duplicate tool feature id: \(id.rawValue)"
    }
}

public struct ToolRegistry: Sendable {
    public let features: [any ToolFeature]
    public let metadata: [ToolMetadata]

    public init(features: [any ToolFeature]) throws {
        var seenIDs = Set<ToolFeatureID>()
        var orderedMetadata: [ToolMetadata] = []

        for feature in features {
            let metadata = feature.metadata
            guard seenIDs.insert(metadata.id).inserted else {
                throw DuplicateToolFeatureID(id: metadata.id)
            }
            orderedMetadata.append(metadata)
        }

        self.features = features
        self.metadata = orderedMetadata
    }

    /// Degraded launch fallback when feature registration fails; cannot throw.
    public init() {
        self.features = []
        self.metadata = []
    }

    public var firstFeatureID: ToolFeatureID? {
        metadata.first?.id
    }

    /// Default sidebar selection when the shell opens: the first tool in sidebar
    /// order that can be the main pane (the Library tool when there is one).
    public var preferredDefaultFeatureID: ToolFeatureID? {
        ToolSection.sidebarOrder(metadata).first { $0.section != .settings }?.id
            ?? firstFeatureID
    }

    public func feature(for id: ToolFeatureID) -> (any ToolFeature)? {
        features.first { $0.metadata.id == id }
    }

    /// `NIKO_MUSIC_HUB_UI_TOOL` — tool id slug for UI review / automation (e.g. `archive-browser`).
    public static func initialToolID(from environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolFeatureID? {
        guard let raw = environment["NIKO_MUSIC_HUB_UI_TOOL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return ToolFeatureID(raw)
    }

    /// Launch selection: `-ui-tool` / `NIKO_MUSIC_HUB_UI_TOOL` wins, then a stored id if registered.
    /// Never restores the Settings tool (`ToolSection.settings`) as the main pane.
    public func resolvedLaunchToolID(
        storedRaw: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolFeatureID? {
        if let override = Self.initialToolID(from: environment) {
            return contentToolID(override)
        }
        if let storedRaw {
            let trimmed = storedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return contentToolID(ToolFeatureID(trimmed))
            }
        }
        return preferredDefaultFeatureID
    }

    private func contentToolID(_ id: ToolFeatureID) -> ToolFeatureID? {
        guard let metadata = feature(for: id)?.metadata, metadata.section != .settings else {
            return preferredDefaultFeatureID
        }
        return metadata.id
    }
}
