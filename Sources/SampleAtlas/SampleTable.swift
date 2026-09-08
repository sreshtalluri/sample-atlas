import SwiftUI
import AppKit
import AtlasCore

/// Native reusable rows provide full-row file dragging, keyboard navigation and
/// incremental loading independently of SwiftUI's preview redraws.
struct SampleTable: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SampleScrollView()
        let table = AuditionTable()
        table.onSpace = { [weak model] in model?.togglePlayback() }
        table.rowHeight = 46; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.backgroundColor = .clear
        for (id, title, width) in [("sound", "Sound", 310.0), ("category", "Type", 85),
                                   ("bpm", "BPM", 55), ("key", "Key", 100), ("length", "Length", 65), ("star", "★", 32)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "sound" ? 180 : 28
            column.maxWidth = .greatestFiniteMagnitude
            column.resizingMask = []
            column.headerCell.alignment = id == "sound" ? .left : .center
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.action = #selector(Coordinator.clicked(_:))
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu(); menu.delegate = context.coordinator; table.menu = menu
        // Reserve a separate scrollbar gutter. Overlay scrollers cover the
        // rightmost favorite button even when the columns fit the viewport.
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.table = table
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let table = coordinator.table else { return }
        if coordinator.revision != model.rowsRevision {
            let appended = coordinator.rows.count < model.results.count && coordinator.rows.first?.id == model.results.first?.id
            coordinator.rows = model.results; coordinator.revision = model.rowsRevision
            coordinator.updating = true
            table.reloadData()
            if let id = model.selectedID, let row = coordinator.rows.firstIndex(where: { $0.id == id }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else { table.deselectAll(nil) }
            coordinator.updating = false
            if !appended { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        let model: AppModel
        weak var table: NSTableView?
        var rows: [Sample] = []
        var revision = -1
        var updating = false
        init(model: AppModel) { self.model = model }
        deinit { NotificationCenter.default.removeObserver(self) }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SampleRow() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            let sample = rows[row]
            if column.identifier.rawValue == "star" {
                let button = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSButton) ?? NSButton()
                button.identifier = column.identifier; button.title = ""
                button.image = NSImage(systemSymbolName: sample.favorite ? "star.fill" : "star", accessibilityDescription: nil)
                button.contentTintColor = sample.favorite ? atlasAccent : .secondaryLabelColor
                button.isBordered = false; button.tag = row; button.target = self; button.action = #selector(favorite(_:))
                button.setAccessibilityLabel(sample.favorite ? "Remove favorite" : "Favorite sample")
                return button
            }
            if column.identifier.rawValue == "sound" {
                let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? SoundCell) ?? SoundCell()
                cell.identifier = column.identifier; cell.title.stringValue = sample.name
                cell.subtitle.stringValue = sample.folder; cell.toolTip = sample.path
                return cell
            }
            let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? CenteredCell) ?? CenteredCell()
            cell.identifier = column.identifier
            let field = cell.label
            field.font = ["bpm", "length"].contains(column.identifier.rawValue) ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
            switch column.identifier.rawValue {
            case "category": field.stringValue = sample.category
            case "bpm": field.stringValue = sample.bpm.map { String(format: "%g", $0) } ?? "—"
            case "key": field.stringValue = sample.key ?? sample.rootNote.map { $0 + " (root)" } ?? "—"
            case "length": field.stringValue = String(format: "%.2fs", sample.duration)
            default: field.stringValue = ""
            }
            cell.toolTip = field.stringValue
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let row = table?.selectedRow, rows.indices.contains(row) else { return }
            model.selectedID = rows[row].id
        }
        @objc func clicked(_ sender: NSTableView) {
            guard rows.indices.contains(sender.clickedRow) else { return }
            model.clicked(rows[sender.clickedRow].id)
        }
        @objc func favorite(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag) else { return }
            model.toggleFavorite(rows[sender.tag])
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else { return nil }
            return rows[row].url as NSURL
        }
        @objc func scrolled(_ notification: Notification) {
            guard !updating, let table else { return }
            let visible = table.rows(in: table.visibleRect)
            if visible.location != NSNotFound && NSMaxRange(visible) >= max(0, rows.count - 30) { model.loadMore() }
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let row = table?.clickedRow, rows.indices.contains(row) else { return }
            let sample = rows[row]
            for (title, action) in [("Reveal in Finder", #selector(revealMenu(_:))), (sample.favorite ? "Remove Favorite" : "Favorite", #selector(favoriteMenu(_:)))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self; item.representedObject = sample; menu.addItem(item)
            }
        }
        @objc func revealMenu(_ sender: NSMenuItem) { if let sample = sender.representedObject as? Sample { model.reveal(sample) } }
        @objc func favoriteMenu(_ sender: NSMenuItem) { if let sample = sender.representedObject as? Sample { model.toggleFavorite(sample) } }
    }
}

@MainActor private let atlasAccent = NSColor(srgbRed: 0.66, green: 0.86, blue: 0.42, alpha: 1)

@MainActor private final class SampleRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        atlasAccent.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}

/// Recalculate from the visible width, including sidebar changes and scroller
/// appearance. The star stays compact; the name receives most of the extra space.
@MainActor private final class SampleScrollView: NSScrollView {
    private var fittedWidth: CGFloat = -1
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView else { return }
        let width = contentSize.width
        guard width > 0, abs(width - fittedWidth) > 0.5 else { return }
        fittedWidth = width
        let weights: [String: CGFloat] = ["sound": 0.54, "category": 0.14, "bpm": 0.075, "key": 0.13, "length": 0.115]
        for column in table.tableColumns {
            column.width = column.identifier.rawValue == "star" ? 32 : (width - 32) * weights[column.identifier.rawValue, default: 0]
        }
        table.setFrameSize(NSSize(width: width, height: table.frame.height))
    }
}

@MainActor private final class CenteredCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .center; label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail; label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label); textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor private final class AuditionTable: NSTableView {
    var onSpace: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty { onSpace?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor private final class SoundCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!)
        icon.contentTintColor = atlasAccent; icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 20)
        ])
        title.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor
        for field in [title, subtitle] {
            field.translatesAutoresizingMaskIntoConstraints = false; field.lineBreakMode = .byTruncatingTail
            addSubview(field)
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10).isActive = true
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        }
        title.topAnchor.constraint(equalTo: topAnchor, constant: 7).isActive = true
        subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3).isActive = true
        textField = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
