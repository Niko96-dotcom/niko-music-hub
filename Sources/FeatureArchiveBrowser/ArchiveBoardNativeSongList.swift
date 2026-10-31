import AppCore
import AppKit
import NikoMusicCore
import ProjectVaultRuntime
import SwiftUI

/// The lane's scrolling boundary. AppKit owns row reuse and the document
/// extent; each realized row renders the existing SwiftUI card unchanged.
struct ArchiveBoardNativeSongList: NSViewRepresentable {
    let songs: [Song]
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    let vaultActivity: [String: String]
    let viewModel: ArchiveBrowserViewModel
    let dropLayout: ArchiveBoardDropLayout
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    var isBoardVisible = true
    var onInteract: () -> Void = {}
    var boardScroll: ArchiveBoardScrollController? = nil

    func makeNSView(context: Context) -> ArchiveBoardNativeSongListView {
        let view = ArchiveBoardNativeSongListView()
        view.apply(self, animated: false)
        return view
    }

    func updateNSView(_ view: ArchiveBoardNativeSongListView, context: Context) {
        view.apply(self, animated: context.transaction.animation != nil && !reduceMotion)
    }
}

final class ArchiveBoardNativeSongListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = ArchiveBoardCardTable()
    private var input: ArchiveBoardNativeSongList?
    private var scrollObservation: ArchiveBoardScrollObservation?
    private var rowByID: [String: Int] = [:]
    private var wasBoardVisible = true
    private var documentHeight: CGFloat = 0
    private var correctionPending = false
    private var enteringIDs: Set<String> = []
    private var entranceGeneration: UInt64 = 0
    private let interaction = ArchiveBoardNativeCardInteraction()
    private static let cellID = NSUserInterfaceItemIdentifier("archive-board-card")
    private static let rowID = NSUserInterfaceItemIdentifier("archive-board-row")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        table.style = .plain
        table.backgroundColor = .clear
        table.headerView = nil
        table.focusRingType = .none
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.rowHeight = 74
        table.usesAutomaticRowHeights = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: Self.cellID)
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        documentView = table
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var acceptsFirstResponder: Bool { false }

    // Routing preserves the event and leaves all movement to AppKit. Keep
    // native responsive scrolling enabled despite overriding scrollWheel.
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if input?.boardScroll?.routeHorizontalWheel(event) == true { return }
        super.scrollWheel(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { scrollObservation = nil }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrollActivity()
    }

    private func observeScrollActivity() {
        scrollObservation = nil
        if window != nil, let activity = input?.boardScroll?.activity {
            scrollObservation = ArchiveBoardScrollObservation(scrollView: self, activity: activity)
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        let height = documentView?.frame.height ?? 0
        let shrank = height < documentHeight - 0.5
        documentHeight = height
        super.reflectScrolledClipView(clipView)
        guard shrank, !correctionPending else { return }
        correctionPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.correctionPending = false
            let clip = self.contentView
            let constrained = clip.constrainBoundsRect(clip.bounds)
            if clip.bounds.minY > constrained.minY + 0.5 {
                clip.scroll(to: constrained.origin)
                self.reflectScrolledClipView(clip)
            }
        }
    }

    func apply(_ next: ArchiveBoardNativeSongList, animated: Bool) {
        let old = input
        let oldRows = rowByID
        input = next
        if old?.boardScroll !== next.boardScroll { observeScrollActivity() }
        next.dropLayout.nativeList = self
        interaction.perform = next.onInteract
        if wasBoardVisible && !next.isBoardVisible {
            var top = contentView.bounds
            top.origin = .zero
            contentView.scroll(to: contentView.constrainBoundsRect(top).origin)
            reflectScrolledClipView(contentView)
        }
        wasBoardVisible = next.isBoardVisible
        let nextIDs = next.songs.map(\.id)
        let oldIDs = old?.songs.map(\.id) ?? []
        var reloaded = false
        if oldIDs != nextIDs {
            rowByID = Dictionary(nextIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            // Only an animated change needs the sets: a search or a filter change is not animated
            // and goes from thousands of rows to a few, so it reloads without hashing every id twice.
            var oldSet: Set<String> = []
            var newSet: Set<String> = []
            var keepsOrder = false
            if animated, old != nil {
                oldSet = Set(oldIDs)
                newSet = Set(nextIDs)
                keepsOrder = oldIDs.filter { newSet.contains($0) } == nextIDs.filter { oldSet.contains($0) }
            }
            if keepsOrder {
                enteringIDs = newSet.subtracting(oldSet)
                entranceGeneration &+= 1
                let generation = entranceGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveBoardMotion.move) { [weak self] in
                    guard let self, self.entranceGeneration == generation else { return }
                    self.enteringIDs = []
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = ArchiveBoardMotion.move
                    context.timingFunction = ArchiveBoardMotion.moveCurve
                    table.beginUpdates()
                    table.removeRows(at: IndexSet(oldIDs.indices.filter { !newSet.contains(oldIDs[$0]) }), withAnimation: .effectFade)
                    table.insertRows(at: IndexSet(nextIDs.indices.filter { !oldSet.contains(nextIDs[$0]) }), withAnimation: .effectGap)
                    table.endUpdates()
                }
            } else {
                enteringIDs = []
                table.reloadData()
                reloaded = true
            }
        }
        // Refresh every realized row, including selection, playback owner,
        // metadata, Vault activity and the color scheme. A realized row can be out
        // of view (the board scrolled the lane sideways, or a song detail hides the
        // board) and is shown again as it is, so visibility must not decide. Rows
        // not realized read the latest input when AppKit asks for them; no old Song
        // values are cached in cells.
        guard !reloaded, let old else { return }
        let selectedRow = next.selectedSongID.flatMap { rowByID[$0] }
        var changedHeights = IndexSet()
        if !old.songs.equalsConcurrently(next.songs) {
            for (row, song) in next.songs.enumerated() {
                if oldRows[song.id].map({ old.songs[$0] }) != song { changedHeights.insert(row) }
            }
        }
        if old.vaultPresentations != next.vaultPresentations || old.vaultActivity != next.vaultActivity {
            for (row, song) in next.songs.enumerated() where
                old.vaultPresentations[song.id] != next.vaultPresentations[song.id]
                    || old.vaultActivity[song.id] != next.vaultActivity[song.id] {
                changedHeights.insert(row)
            }
        }
        table.enumerateAvailableRowViews { rowView, row in
            guard next.songs.indices.contains(row) else { return }
            (rowView as? ArchiveBoardCardRow)?.showsSeparator =
                Self.showsSeparator(below: row, count: next.songs.count, selectedRow: selectedRow)
            let song = next.songs[row]
            let previousSong = oldRows[song.id].map { old.songs[$0] }
            let contentChanged = previousSong != song
                || old.vaultPresentations[song.id] != next.vaultPresentations[song.id]
                || old.vaultActivity[song.id] != next.vaultActivity[song.id]
            let selectionChanged = (old.selectedSongID == song.id) != (next.selectedSongID == song.id)
            guard contentChanged || selectionChanged || old.viewModel !== next.viewModel
                    || old.colorScheme != next.colorScheme || old.reduceMotion != next.reduceMotion
                    || old.boardScroll !== next.boardScroll else { return }
            if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArchiveBoardCardCell {
                cell.setCard(card(at: row), colorScheme: next.colorScheme,
                             interaction: interaction, width: table.tableColumns[0].width,
                             scrollActivity: next.boardScroll?.activity, reduceMotion: next.reduceMotion)
            }
            if contentChanged { changedHeights.insert(row) }
        }
        if !changedHeights.isEmpty { table.noteHeightOfRows(withIndexesChanged: changedHeights) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { input?.songs.count ?? 0 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let input, input.songs.indices.contains(row) else { return nil }
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? ArchiveBoardCardCell) ?? ArchiveBoardCardCell()
        cell.identifier = Self.cellID
        cell.setCard(card(at: row), colorScheme: input.colorScheme,
                     insertionAnimated: enteringIDs.contains(input.songs[row].id), interaction: interaction,
                     width: table.tableColumns[0].width, scrollActivity: input.boardScroll?.activity,
                     reduceMotion: input.reduceMotion)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = (tableView.makeView(withIdentifier: Self.rowID, owner: nil) as? ArchiveBoardCardRow) ?? ArchiveBoardCardRow()
        view.identifier = Self.rowID
        if let input {
            view.showsSeparator = Self.showsSeparator(
                below: row, count: input.songs.count,
                selectedRow: input.selectedSongID.flatMap { rowByID[$0] })
        }
        return view
    }

    /// A hairline between two rows, but none under the last row and none
    /// touching the selected row, whose pill stands on its own.
    static func showsSeparator(below row: Int, count: Int, selectedRow: Int?) -> Bool {
        row < count - 1 && selectedRow != row && selectedRow != row + 1
    }

    /// Brings a dropped song's row into sight, at the pace the lanes move,
    /// where its row fades in, and marks it with the landed pill. Lanes sort
    /// by recent activity, so a drop can land far from where it was let go.
    /// A selected row has its pill already.
    func revealDroppedSong(songID: String, reduceMotion: Bool) {
        guard let row = rowByID[songID] else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : ArchiveBoardMotion.move
            context.timingFunction = ArchiveBoardMotion.moveCurve
            context.allowsImplicitAnimation = !reduceMotion
            table.scrollRowToVisible(row)
        }
        if input?.selectedSongID != songID {
            (table.rowView(atRow: row, makeIfNecessary: true) as? ArchiveBoardCardRow)?.markLanded(reduceMotion: reduceMotion)
        }
    }

    func cardFrame(for id: String) -> CGRect? {
        guard let row = rowByID[id],
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArchiveBoardCardCell else { return nil }
        var ancestor = superview
        while let view = ancestor {
            if view is any ArchiveBoardColumnFrameSpace { return cell.cardFrame(in: view) }
            ancestor = view.superview
        }
        return nil
    }

    private func card(at row: Int) -> ArchiveBoardSongCard {
        guard let input else { preconditionFailure("A row requires current input") }
        let song = input.songs[row]
        return ArchiveBoardSongCard(
            song: song,
            isSelected: input.selectedSongID == song.id,
            vaultPresentation: input.vaultPresentations[song.id],
            vaultActivityMessage: input.vaultActivity[song.id],
            viewModel: input.viewModel,
            scrollActivity: input.boardScroll?.activity
        )
    }
}

private final class ArchiveBoardCardTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

/// Draws only the hairline under its row; the list decides which rows have
/// one. AppKit drawing keeps the line out of the SwiftUI row, and the
/// separator color resolves from the window's appearance.
final class ArchiveBoardCardRow: NSTableRowView {
    var showsSeparator = false {
        didSet { if showsSeparator != oldValue { needsDisplay = true } }
    }

    private var landedMark: NSView?
    var showsLandedMark: Bool { landedMark != nil }
    static let landedFade: TimeInterval = 0.8

    /// The selection pill drawn like the SwiftUI one (color, corner, bottom
    /// inset) under the row's content. It fades in with the dropped row, then
    /// out, so the eye finds the song in its new place.
    func markLanded(reduceMotion: Bool) {
        landedMark?.removeFromSuperview()
        var frame = bounds
        frame.size.height -= 1
        if !isFlipped { frame.origin.y += 1 }
        let mark = NSView(frame: frame)
        mark.autoresizingMask = [.width, .height]
        mark.wantsLayer = true
        mark.layer?.cornerRadius = HubDesignSystem.Radius.row
        mark.layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            mark.layer?.backgroundColor = NSColor(HubDesignSystem.Palette.selection).cgColor
        }
        mark.alphaValue = reduceMotion ? 1 : 0
        addSubview(mark, positioned: .below, relativeTo: nil)
        landedMark = mark
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : ArchiveBoardMotion.move
            context.timingFunction = ArchiveBoardMotion.moveCurve
            mark.animator().alphaValue = 1
        } completionHandler: { [weak self, weak mark] in
            MainActor.assumeIsolated { self?.fadeOutLandedMark(mark) }
        }
    }

    private func fadeOutLandedMark(_ mark: NSView?) {
        guard let mark, mark === landedMark else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.landedFade
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mark.animator().alphaValue = 0
        } completionHandler: { [weak self, weak mark] in
            MainActor.assumeIsolated {
                mark?.removeFromSuperview()
                if let self, self.landedMark === mark { self.landedMark = nil }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        landedMark?.removeFromSuperview()
        landedMark = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard showsSeparator else { return }
        let inset = ArchiveBoardCardView.rowInset
        let y = isFlipped ? bounds.maxY - 1 : bounds.minY
        NSColor(HubDesignSystem.Palette.separator).setFill()
        NSRect(x: bounds.minX + inset, y: y, width: max(0, bounds.width - 2 * inset), height: 1).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class ArchiveBoardCardCell: NSTableCellView {
    private var host: NSHostingController<ArchiveBoardCardContent>?
    private var heightConstraint: NSLayoutConstraint?
    private var measuredWidth: CGFloat = 0
    private var needsMeasurement = true

    var displayedContent: ArchiveBoardCardContent? { host?.rootView }

    func setCard(_ card: ArchiveBoardSongCard, colorScheme: ColorScheme,
                 insertionAnimated: Bool = false, interaction: ArchiveBoardNativeCardInteraction, width: CGFloat,
                 scrollActivity: ArchiveBoardScrollActivity? = nil, reduceMotion: Bool = false) {
        if let old = host?.rootView, old.card.song.id != card.song.id || old.card.song.workflowStatus != card.song.workflowStatus {
            old.scrollActivity?.removeHover(songID: old.card.song.id, laneID: old.card.song.workflowStatus?.rawValue)
        }
        let content = ArchiveBoardCardContent(card: card, colorScheme: colorScheme,
                                             insertionAnimated: insertionAnimated, interaction: interaction,
                                             scrollActivity: scrollActivity, reduceMotion: reduceMotion)
        if let host {
            host.rootView = content
        } else {
            let host = NSHostingController(rootView: content)
            // We supply the measured width and natural height. The default
            // min/ideal/max proposals would repeat those layout measurements.
            host.sizingOptions = []
            let hosted = host.view
            hosted.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosted)
            let height = hosted.heightAnchor.constraint(equalToConstant: 68)
            NSLayoutConstraint.activate([
                hosted.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosted.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosted.topAnchor.constraint(equalTo: topAnchor),
                hosted.bottomAnchor.constraint(equalTo: bottomAnchor),
                height,
            ])
            self.host = host
            heightConstraint = height
        }
        needsMeasurement = true
        measure(at: width)
    }

    override func layout() {
        super.layout()
        measure(at: bounds.width)
    }

    private func measure(at width: CGFloat) {
        guard let host, width > 0, needsMeasurement || abs(width - measuredWidth) > 0.5 else { return }
        let measured = host.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude))
        heightConstraint?.constant = measured.height
        measuredWidth = width
        needsMeasurement = false
    }

    func cardFrame(in view: NSView) -> CGRect? { host.map { $0.view.convert($0.view.bounds, to: view) } }
}

struct ArchiveBoardCardContent: View {
    let card: ArchiveBoardSongCard
    let colorScheme: ColorScheme
    var insertionAnimated = false
    let interaction: ArchiveBoardNativeCardInteraction
    var scrollActivity: ArchiveBoardScrollActivity? = nil
    var reduceMotion = false

    var body: some View {
        card.equatable()
            .fixedSize(horizontal: false, vertical: true)
            .modifier(ArchiveBoardCardEntrance(animated: insertionAnimated && !reduceMotion))
            .simultaneousGesture(TapGesture().onEnded { interaction.perform() })
            .id(card.song.id)
            .environment(\.colorScheme, colorScheme)
    }
}

/// Crosses the native row-hosting boundary without retaining an old callback
/// when the parent refreshes its keyboard-focus owner.
@MainActor
final class ArchiveBoardNativeCardInteraction {
    var perform: () -> Void = {}
}

private struct ArchiveBoardCardEntrance: ViewModifier {
    let animated: Bool
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(animated && !appeared ? 0 : 1)
            .offset(y: animated && !appeared ? 4 : 0)
            .onAppear {
                if animated { withAnimation(ArchiveBoardMotion.moveAnimation) { appeared = true } }
            }
    }
}
