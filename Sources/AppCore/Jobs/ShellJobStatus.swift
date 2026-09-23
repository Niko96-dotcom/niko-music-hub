import Foundation

/// Running-job snapshot for the production shell (NMH-011).
public struct ShellJobStatus: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var percent: Double?
    public var cancelActionID: String?
    /// When set, `displayLine` wraps `title` as `{verb} “{title}”`.
    public var activityVerb: String?
    /// Tool that started a `JobRunner` job; `nil` for extra (archive) sources.
    public var sourceToolID: ToolFeatureID?

    public init(
        id: String,
        title: String,
        percent: Double? = nil,
        cancelActionID: String? = nil,
        activityVerb: String? = nil,
        sourceToolID: ToolFeatureID? = nil
    ) {
        self.id = id
        self.title = title
        self.percent = percent
        self.cancelActionID = cancelActionID
        self.activityVerb = activityVerb
        self.sourceToolID = sourceToolID
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
            activityVerb: activityVerb(for: job.sourceToolID),
            sourceToolID: job.sourceToolID
        )
    }

    public static func activityVerb(for sourceToolID: ToolFeatureID) -> String {
        switch sourceToolID.rawValue {
        case "downloader":
            return "Downloading"
        case "stem-separation":
            return "Separating"
        case "wav-converter":
            return "Converting"
        default:
            return "Running"
        }
    }
}

public enum ShellJobExtraSourceID: Sendable {
    public static let converter = "wav-converter"
    public static let archiveScan = "archive-scan"
    public static let vaultTransfer = "vault-transfer"
}

/// Converter reporting hook (NMH-011). Maps conversion-task state to a shell job.
public enum ConverterJobReporting: Sendable {
    public static func status(
        isConverting: Bool,
        filename: String?,
        percent: Double
    ) -> ShellJobStatus? {
        ShellJobStatusCopy.converterStatus(
            isConverting: isConverting,
            filename: filename,
            percent: percent
        )
    }
}

public enum ShellJobStatusCopy: Sendable {
    public static let cancel = CancelCopy.cancelOperation
    public static let scanningArchive = "Scanning archive"
    public static let vaultTransferFallback = "Project Vault transfer"
    public static let converterFallback = "WAV Converter"
    public static let converterCancelHelp =
        "Stops converting now and skips the rest. Verified WAV files are kept."

    public static func multipleJobsTitle(count: Int) -> String {
        "\(count) jobs running"
    }

    public static func converterStatus(
        isConverting: Bool,
        filename: String?,
        percent: Double
    ) -> ShellJobStatus? {
        guard isConverting else { return nil }
        let resolvedPercent: Double? = percent > 0 ? percent : nil
        if let filename, !filename.isEmpty {
            return ShellJobStatus(
                id: ShellJobExtraSourceID.converter,
                title: filename,
                percent: resolvedPercent,
                cancelActionID: ShellJobExtraSourceID.converter,
                activityVerb: "Converting"
            )
        }
        return ShellJobStatus(
            id: ShellJobExtraSourceID.converter,
            title: converterFallback,
            percent: resolvedPercent,
            cancelActionID: ShellJobExtraSourceID.converter
        )
    }

    /// NMH-054: vault restore row. `percent` is the honest staging fraction
    /// (nil while totals are unknown), so the jobs row reads determinate
    /// (`Transferring “Song” · 42%`) exactly when the detail bar does.
    public static func vaultTransferStatus(
        songName: String,
        progress: ProjectVaultRestoreProgress?
    ) -> ShellJobStatus {
        ShellJobStatus(
            id: ShellJobExtraSourceID.vaultTransfer,
            title: songName.isEmpty ? vaultTransferFallback : songName,
            percent: progress?.fraction,
            cancelActionID: ShellJobExtraSourceID.vaultTransfer,
            activityVerb: "Transferring"
        )
    }
}
