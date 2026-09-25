import Foundation

enum UILaunchTool {
    /// Parses `-ui-tool <id>` (from `open --args`) without side effects.
    static func toolID(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-ui-tool"),
              index + 1 < arguments.count else {
            return nil
        }
        let toolID = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolID.isEmpty else { return nil }
        return toolID
    }

    /// Applies `-ui-tool <id>` from `open --args` before SwiftUI builds the shell.
    /// Must run before `AppComposition.make()` resolves the launch selection once;
    /// anything later never takes effect (the shell only reads `selectedToolID`).
    static func applyFromLaunchArguments(_ arguments: [String] = CommandLine.arguments) {
        guard let toolID = toolID(from: arguments) else { return }
        setenv("NIKO_MUSIC_HUB_UI_TOOL", toolID, 1)
    }
}
