import Foundation

/// Which in-app activity Esc / ⌘. cancels (NMH-009). Pure routing over the
/// `ShellJobStatusCenter` job list so the policy is unit-testable; the menu
/// commands live in `HubCancelCommands`.
public enum InAppJobCancelTarget: Equatable, Sendable {
    case download
    case stemSeparation
    case conversion
    case vaultTransfer
    case scan
}

/// Which cancellable activities the shell job list currently holds.
public struct InAppJobActivity: Equatable, Sendable {
    public static let downloaderToolID = ToolFeatureID("downloader")
    /// Covers file separations and the YouTube-to-stems workflow; both run as one
    /// `JobRunner` job under the stem tool.
    public static let stemSeparationToolID = ToolFeatureID("stem-separation")
    public static let converterToolID = ToolFeatureID("wav-converter")
    public static let archiveBrowserToolID = ToolFeatureID("archive-browser")

    public let jobs: [ShellJobStatus]

    public init(jobs: [ShellJobStatus]) {
        self.jobs = jobs
    }

    public var hasDownload: Bool { !jobs(for: .download).isEmpty }
    public var hasStemSeparation: Bool { !jobs(for: .stemSeparation).isEmpty }
    public var hasConversion: Bool { !jobs(for: .conversion).isEmpty }
    public var hasActiveVaultTransfer: Bool { !jobs(for: .vaultTransfer).isEmpty }
    public var isScanning: Bool { !jobs(for: .scan).isEmpty }

    public func jobs(for target: InAppJobCancelTarget) -> [ShellJobStatus] {
        switch target {
        case .download:
            jobs.filter { $0.sourceToolID == Self.downloaderToolID }
        case .stemSeparation:
            jobs.filter { $0.sourceToolID == Self.stemSeparationToolID }
        case .conversion:
            jobs.filter { $0.id == ShellJobExtraSourceID.converter }
        case .vaultTransfer:
            jobs.filter { $0.id == ShellJobExtraSourceID.vaultTransfer }
        case .scan:
            jobs.filter { $0.id == ShellJobExtraSourceID.archiveScan }
        }
    }
}

public enum InAppJobCancelRouting {
    /// Esc: a tool pane that owns its jobs cancels only its own job; the
    /// archive browser keeps Esc for itself; elsewhere a vault transfer or scan.
    public static func escapeTarget(
        selectedToolID: ToolFeatureID?,
        _ activity: InAppJobActivity
    ) -> InAppJobCancelTarget? {
        if selectedToolID == InAppJobActivity.downloaderToolID {
            return activity.hasDownload ? .download : nil
        }
        if selectedToolID == InAppJobActivity.stemSeparationToolID {
            return activity.hasStemSeparation ? .stemSeparation : nil
        }
        if selectedToolID == InAppJobActivity.converterToolID {
            return activity.hasConversion ? .conversion : nil
        }
        if selectedToolID == InAppJobActivity.archiveBrowserToolID {
            return nil
        }
        if activity.hasActiveVaultTransfer { return .vaultTransfer }
        if activity.isScanning { return .scan }
        return nil
    }

    /// ⌘.: the foremost running activity regardless of the selected tool.
    public static func foremost(_ activity: InAppJobActivity) -> InAppJobCancelTarget? {
        if activity.hasDownload { return .download }
        if activity.hasStemSeparation { return .stemSeparation }
        if activity.hasConversion { return .conversion }
        if activity.hasActiveVaultTransfer { return .vaultTransfer }
        if activity.isScanning { return .scan }
        return nil
    }
}
