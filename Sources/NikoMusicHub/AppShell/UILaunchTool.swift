import Foundation

enum UILaunchTool {
    /// Applies `-ui-tool <id>` from `open --args` before SwiftUI builds the shell.
    static func applyFromLaunchArguments() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-ui-tool"),
              index + 1 < arguments.count else {
            return
        }
        let toolID = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolID.isEmpty else { return }
        setenv("NIKO_MUSIC_HUB_UI_TOOL", toolID, 1)
    }
}
