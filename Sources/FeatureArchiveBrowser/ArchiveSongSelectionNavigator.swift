import NikoMusicCore
import SwiftUI

enum ArchiveSongMoveDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right

    init(_ command: MoveCommandDirection) {
        switch command {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        @unknown default: self = .down
        }
    }
}

/// Keyboard selection among filtered songs (list) and visual board columns.
enum ArchiveSongSelectionNavigator {
    static func move(
        direction: ArchiveSongMoveDirection,
        songs: [Song],
        selectedID: String?
    ) -> Song? {
        linearMove(direction: direction, songs: songs, selectedID: selectedID)
    }

    static func moveOnBoard(
        direction: ArchiveSongMoveDirection,
        songs: [Song],
        selectedID: String?,
        preservingOrder: Bool = false
    ) -> Song? {
        let occupied = ArchiveBoardProjection.columns(from: songs, preservingOrder: preservingOrder)
            .filter { !$0.songs.isEmpty }
        guard !occupied.isEmpty else { return nil }

        switch direction {
        case .left, .right:
            return moveAcrossColumns(direction: direction, columns: occupied, selectedID: selectedID)
        case .up, .down:
            return moveWithinColumn(direction: direction, columns: occupied, selectedID: selectedID)
        }
    }

    private static func linearMove(
        direction: ArchiveSongMoveDirection,
        songs: [Song],
        selectedID: String?
    ) -> Song? {
        guard !songs.isEmpty else { return nil }
        guard let selectedID, let index = songs.firstIndex(where: { $0.id == selectedID }) else {
            return (direction == .up || direction == .left) ? songs.last : songs.first
        }
        switch direction {
        case .down, .right:
            let next = index + 1
            return next < songs.count ? songs[next] : songs[index]
        case .up, .left:
            let previous = index - 1
            return previous >= 0 ? songs[previous] : songs[index]
        }
    }

    private static func moveAcrossColumns(
        direction: ArchiveSongMoveDirection,
        columns: [ArchiveBoardColumn],
        selectedID: String?
    ) -> Song? {
        guard let selectedID,
              let columnIndex = columns.firstIndex(where: { $0.songs.contains { $0.id == selectedID } })
        else {
            return columns.first?.songs.first
        }
        let delta = direction == .right ? 1 : -1
        let nextIndex = columnIndex + delta
        guard columns.indices.contains(nextIndex) else {
            return columns[columnIndex].songs.first { $0.id == selectedID }
        }
        return columns[nextIndex].songs.first
    }

    private static func moveWithinColumn(
        direction: ArchiveSongMoveDirection,
        columns: [ArchiveBoardColumn],
        selectedID: String?
    ) -> Song? {
        guard let selectedID,
              let column = columns.first(where: { $0.songs.contains { $0.id == selectedID } })
        else {
            return direction == .up ? columns.last?.songs.last : columns.first?.songs.first
        }
        return linearMove(direction: direction, songs: column.songs, selectedID: selectedID)
    }
}
