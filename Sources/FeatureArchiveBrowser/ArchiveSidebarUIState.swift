import SwiftUI

/// Sidebar-only disclosure expansion (not archive domain state).
@MainActor
final class ArchiveSidebarUIState: ObservableObject {
    @Published var morePanelExpanded = false
    @Published var rootsSectionExpanded = false
}
