import SwiftUI
import AppKit
import AtlasCore

/// Native reusable rows provide full-row file dragging, keyboard navigation and
/// incremental loading independently of SwiftUI's preview redraws.
struct SampleTable: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = AuditionTable()
        table.onSpace = { [weak model] in model?.togglePlayback() }
        table.rowHeight = 48; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("sound", "Sound / folder", 310.0), ("category", "Type", 85), ("kind", "Kind", 80),
                                   ("bpm", "BPM", 55), ("key", "Key / root", 100), ("format", "File", 50), ("length", "Length", 65), ("star", "★", 30)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "sound" ? 180 : width
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.action = #selector(Coordinator.clicked(_:))
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu(); menu.delegate = context.coordinator; table.menu = menu
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
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
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            let sample = rows[row]
            if column.identifier.rawValue == "star" {
                let button = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSButton) ?? NSButton()
                button.identifier = column.identifier; button.title = sample.favorite ? "★" : "☆"
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
            let field = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
            field.identifier = column.identifier; field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor
            switch column.identifier.rawValue {
            case "category": field.stringValue = sample.category
            case "kind": field.stringValue = sample.kind
            case "bpm": field.stringValue = sample.bpm.map { String(format: "%g", $0) } ?? "—"
            case "key": field.stringValue = sample.key ?? sample.rootNote.map { $0 + " (root)" } ?? "—"
            case "format": field.stringValue = sample.url.pathExtension.uppercased()
            case "length": field.stringValue = String(format: "%.2fs", sample.duration)
            default: field.stringValue = ""
            }
            return field
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
        title.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor
        for field in [title, subtitle] {
            field.translatesAutoresizingMaskIntoConstraints = false; field.lineBreakMode = .byTruncatingTail
            addSubview(field)
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        }
        title.topAnchor.constraint(equalTo: topAnchor, constant: 7).isActive = true
        subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3).isActive = true
        textField = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
