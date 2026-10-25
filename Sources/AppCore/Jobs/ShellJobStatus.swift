import Foundation
import NikoMusicCore

/// Running-job snapshot for the production shell (NMH-011).
public struct ShellJobStatus: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var percent: Double?
    public var cancelActionID: String?
    /// When set, `displayLine` wraps `title` as `{verb} “{title}”`.
    public var activityVerb: String?
    /// The tool whose job this is: Esc cancels it on that tool's pane (NMH-009).
    /// `nil` for shell work (archive scan, Vault transfer), which Esc cancels from
    /// a pane that does not handle Esc.
    public var sourceToolID: ToolFeatureID?
    /// What Esc and ⌘. cancel this job as (`InAppJobCancelRouting`); `nil`: only
    /// the jobs strip's Cancel reaches it.
    public var cancelTarget: InAppJobCancelTarget?
    /// Help of the jobs strip's Cancel button; `nil` uses its title.
    public var cancelHelp: String?
    /// Quit asks before cutting this off (ADR-019). A background archive scan is
    /// read-only and safe to stop, so it is shown but does not block quit.
    public var blocksQuit: Bool
    /// Shown in the jobs strip and reachable by ⌘. (ADR-019). A recorder take
    /// or a helper install counts at quit but has its own controls, so it
    /// registers unlisted.
    public var listed: Bool

    public init(
        id: String,
        title: String,
        percent: Double? = nil,
        cancelActionID: String? = nil,
        activityVerb: String? = nil,
        sourceToolID: ToolFeatureID? = nil,
        cancelTarget: InAppJobCancelTarget? = nil,
        cancelHelp: String? = nil,
        blocksQuit: Bool = true,
        listed: Bool = true
    ) {
        self.id = id
        self.title = title
        self.percent = percent
        self.cancelActionID = cancelActionID
        self.activityVerb = activityVerb
        self.sourceToolID = sourceToolID
        self.cancelTarget = cancelTarget
        self.cancelHelp = cancelHelp
        self.blocksQuit = blocksQuit
        self.listed = listed
    }

    public var displayLine: String {
        let head: String
        if let activityVerb, !activityVerb.isEmpty {
            head = "\(activityVerb) “\(title)”"
        } else {
            head = title
        }
        guard let percent else { return head }
        return "\(head) · \(Int((percent * 100).rounded()))%"
    }

    public static func fromJob(_ job: Job) -> ShellJobStatus {
        ShellJobStatus(
            id: job.id.uuidString,
            title: job.title,
            percent: job.progress > 0 ? job.progress : nil,
            cancelActionID: job.id.uuidString,
            activityVerb: job.activityVerb,
            sourceToolID: job.sourceToolID,
            cancelTarget: job.cancelTarget
        )
    }
}

public enum ShellJobExtraSourceID: Sendable {
    public static let converter = "wav-conversion"
    public static let archiveScan = "archive-scan"
    public static let vaultTransfer = "vault-transfer"
    public static let audioRecorder = "recorder-take"
    public static let helperInstall = "helper-install"
    public static let downloadStart = "download-start"
}

public enum ShellJobStatusCopy: Sendable {
    public static let cancel = CancelCopy.cancelOperation
    public static let scanningArchive = "Scanning archive"
    public static let recordingTake = "Recording system audio"
    public static let installingHelperTools = "Installing helper tools"

    public static func multipleJobsTitle(count: Int) -> String {
        "\(CountCopy.count(count, "job")) running"
    }

    /// The archive scan row: shell work, stopped by Esc on a pane that does not
    /// handle Esc, after a Vault transfer.
    public static let archiveScanStatus = ShellJobStatus(
        id: ShellJobExtraSourceID.archiveScan,
        title: scanningArchive,
        cancelActionID: ShellJobExtraSourceID.archiveScan,
        cancelTarget: .scan,
        blocksQuit: false
    )
}
