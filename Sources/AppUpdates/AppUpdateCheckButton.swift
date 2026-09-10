import SwiftUI

/// The "Check for Updates…" menu item.
///
/// Exposed as a `View` rather than its own `Commands` type so the app menu can
/// compose it into the single `CommandGroup(replacing: .appInfo)` it already
/// uses for About. That keeps both items in one group, which is where macOS
/// users expect to find this action.
public struct AppUpdateCheckButton: View {
    @ObservedObject private var controller: AppUpdateController

    public init(controller: AppUpdateController) {
        self.controller = controller
    }

    public var body: some View {
        Button("Check for Updates…") {
            controller.checkForUpdates()
        }
        .disabled(!controller.canCheckForUpdates || controller.status.isBusy)
    }
}
