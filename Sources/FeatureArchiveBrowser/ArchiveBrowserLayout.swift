import CoreGraphics

enum ArchiveBrowserLayout {
    static let listMinWidth: CGFloat = 260
    static let listMaxWidth: CGFloat = 300
    static let listWidthRatio: CGFloat = 0.26
    /// Narrower than this, the list and detail pane alternate instead of splitting.
    static let splitViewMinWidth: CGFloat = 780

    static func listWidth(totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return listMinWidth }
        let proposed = totalWidth * listWidthRatio
        return min(listMaxWidth, max(listMinWidth, proposed))
    }

    static func isCompactList(_ listWidth: CGFloat) -> Bool {
        listWidth < 300
    }
}
