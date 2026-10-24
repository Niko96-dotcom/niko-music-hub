import AppCore
import Foundation

/// The converter's row in the shell's jobs strip (NMH-011): a WAV Converter job
/// that Esc cancels on the converter's pane and ⌘. after downloads and stem
/// separations (NMH-009).
public enum ConverterJobReporting: Sendable {
    public static let fallbackTitle = "WAV Converter"
    public static let cancelHelp = "Stops converting now and skips the rest. Verified WAV files are kept."

    public static func status(
        isConverting: Bool,
        filename: String?,
        percent: Double
    ) -> ShellJobStatus? {
        guard isConverting else { return nil }
        let filename = filename.flatMap { $0.isEmpty ? nil : $0 }
        return ShellJobStatus(
            id: ShellJobExtraSourceID.converter,
            title: filename ?? fallbackTitle,
            percent: percent > 0 ? percent : nil,
            cancelActionID: ShellJobExtraSourceID.converter,
            // Without a file name the row reads "WAV Converter", not "Converting “WAV Converter”".
            activityVerb: filename == nil ? nil : "Converting",
            sourceToolID: .wavConverter,
            cancelTarget: .conversion,
            cancelHelp: cancelHelp
        )
    }
}
