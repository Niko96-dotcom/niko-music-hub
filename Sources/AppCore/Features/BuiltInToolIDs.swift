import Foundation

/// The built-in tools' IDs, each defined once (`ToolIDSourceTests`). Each feature's
/// metadata uses its own; the shell names a tool only for a curated list (the menu
/// bar menu), a cross-tool request (Search Archive…, a converter hand-off) or a
/// stored item's rule (`OutputHandoff`). An ID is stored (the shell's selection,
/// inbox items) and typed (`-ui-tool`), so it never changes.
public extension ToolFeatureID {
    static let archiveBrowser: ToolFeatureID = "archive-browser"
    static let bpmTapper: ToolFeatureID = "bpm-tapper"
    static let wavConverter: ToolFeatureID = "wav-converter"
    static let audioRecorder: ToolFeatureID = "audio-recorder"
    static let downloader: ToolFeatureID = "downloader"
    static let stemSeparation: ToolFeatureID = "stem-separation"
}
