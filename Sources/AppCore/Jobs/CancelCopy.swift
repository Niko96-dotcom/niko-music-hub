import Foundation

/// Shared in-app cancel copy for downloads, archive scans, and Project Vault transfers (NMH-009).
public enum CancelCopy: Sendable {
    public static let cancelDownload = "Cancel Download"
    public static let cancelScan = "Cancel Scan"
    public static let cancelTransfer = "Cancel Transfer"
    public static let cancelQueuedRequest = "Cancel queued request"
    public static let cancelOperation = "Cancel"

    public static let scanCanceled = "Scan canceled. Songs already in the catalog stay available."

    public static let stopTransferTitle = "Stop this transfer?"
    public static let stopTransferMessage =
        "Niko Music Hub will stop the Project Vault transfer at the next safe point. Files already copied stay in the archive. The Active Projects folder is not deleted. You may need Recover Verified Project if a copy was interrupted."
    public static let keepTransferring = "Keep Transferring"
    public static let stopTransfer = "Stop Transfer"
    public static let transferStopped =
        "Transfer stopped. Files already copied stay in the archive. The Active Projects folder is not deleted."
}
