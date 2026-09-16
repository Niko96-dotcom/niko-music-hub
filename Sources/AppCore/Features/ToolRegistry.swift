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

    /// Default sidebar selection when the shell opens.
    public var preferredDefaultFeatureID: ToolFeatureID? {
        feature(for: "archive-browser")?.metadata.id
            ?? feature(for: "wav-converter")?.metadata.id
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
    /// Never restores `settings` as the main pane.
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
        if id == ToolFeatureID("settings") {
            return preferredDefaultFeatureID
        }
        return feature(for: id)?.metadata.id ?? preferredDefaultFeatureID
    }
}
