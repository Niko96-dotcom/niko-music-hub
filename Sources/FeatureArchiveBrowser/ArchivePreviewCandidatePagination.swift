import Foundation

/// Keeps the Detail screen bounded when an archive folder contains a large number
/// of alternate renders. A single screen only owns one small page; navigating the
/// page replaces those rows instead of mounting every candidate at once.
struct ArchivePreviewCandidatePage<Element> {
    let elements: [Element]
    let index: Int
    let pageCount: Int
    let totalCount: Int

    var hasPreviousPage: Bool { index > 0 }
    var hasNextPage: Bool { index + 1 < pageCount }
}

enum ArchivePreviewCandidatePagination {
    /// A detail page stays small enough that each candidate can retain a rich
    /// transport without making a large session laggy.
    static let defaultPageSize = 24

    static func page<Element>(
        from elements: [Element],
        requestedIndex: Int,
        pageSize: Int = defaultPageSize
    ) -> ArchivePreviewCandidatePage<Element> {
        let resolvedPageSize = max(pageSize, 1)

        let pageCount = max(1, (elements.count + resolvedPageSize - 1) / resolvedPageSize)
        let index = min(max(requestedIndex, 0), pageCount - 1)
        let start = min(index * resolvedPageSize, elements.count)
        let end = min(start + resolvedPageSize, elements.count)

        return ArchivePreviewCandidatePage(
            elements: Array(elements[start..<end]),
            index: index,
            pageCount: pageCount,
            totalCount: elements.count
        )
    }
}
