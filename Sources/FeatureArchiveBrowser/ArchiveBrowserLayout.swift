import CoreGraphics

enum ArchiveBrowserLayout {
    static let listMinWidth: CGFloat = 220
    static let listMaxWidth: CGFloat = 360
    static let listWidthRatio: CGFloat = 0.42

    static func listWidth(totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return listMinWidth }
        let proposed = totalWidth * listWidthRatio
        return min(listMaxWidth, max(listMinWidth, proposed))
    }

    static func isCompactList(_ listWidth: CGFloat) -> Bool {
        listWidth < 300
    }
}
