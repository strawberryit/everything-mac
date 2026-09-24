import SwiftUI
import AppKit
import IndexCore
import UniformTypeIdentifiers
import QuickLookUI

struct ResultsTable: NSViewRepresentable {
    @AppStorage(Styling.fontSizeKey) private var fontSize = Styling.defaultFontSize
    var rows: [FileRecord]
    var onSort: (QueryEngine.SortKey, Bool) -> Void
    var onSelect: (FileRecord?) -> Void
    var onActivate: (FileRecord) -> Void
    var onRenamed: (FileRecord) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RenameTableView()
        table.renameSelected = { [weak coordinator = context.coordinator] in
            guard let coordinator, let table = coordinator.table else { return }
            coordinator.beginRename(row: table.selectedRow)
        }
        table.previewSelected = { [weak coordinator = context.coordinator] in
            guard let coordinator, let table = coordinator.table else { return }
            coordinator.showPreview(row: table.selectedRow, toggle: true)
        }
        // Let dragged columns grow beyond the viewport without shrinking neighbors.
        table.columnAutoresizingStyle = .noColumnAutoresizing
        for (key, title, width) in [("name","Name",260),("path","Path",380),("size","Size",90),("kind","Kind",130),("mtime","Date Modified",160)] {
            let col = NSTableColumn(identifier: .init(key))
            col.title = title; col.width = CGFloat(width)
            col.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(col)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = max(17, ceil(NSFont.systemFont(ofSize: fontSize).boundingRectForFont.height) + 2)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        // Right-click context menu — items target the coordinator; coordinator
        // resolves the clicked row at action time via table.clickedRow. The
        // "Open With" submenu is per-file, so it's rebuilt lazily by the coordinator
        // (its menu delegate) when the user hovers it — see menuNeedsUpdate.
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            mi.target = context.coordinator
            menu.addItem(mi)
        }
        add("Open", #selector(Coordinator.ctxOpen))
        add("Quick Look", #selector(Coordinator.ctxPreview))
        let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let openWithSub = NSMenu(title: "Open With")
        openWithSub.delegate = context.coordinator
        openWith.submenu = openWithSub
        menu.addItem(openWith)
        context.coordinator.openWithMenu = openWithSub
        menu.addItem(.separator())
        add("Reveal in Finder", #selector(Coordinator.ctxReveal))
        add("Copy Path", #selector(Coordinator.ctxCopyPath))
        add("Copy Name", #selector(Coordinator.ctxCopyName))
        add("Rename…", #selector(Coordinator.ctxRename))
        menu.addItem(.separator())
        add("Move to Trash", #selector(Coordinator.ctxTrash))
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        // Keep the edited row stable while live results or sort order change.
        if coord.editingRecord != nil {
            coord.pendingParent = self
            return
        }
        let table = nsView.documentView as? NSTableView
        // Pin selection to the FILE, not the row index. A live-index refresh replaces
        // `results` ~constantly (FSEvents fires for any file change anywhere), and a
        // plain reloadData drops or visually shifts the highlight out from under the
        // user's click. Capture the selected record's stable store id from the OLD
        // rows, reload, then re-select that same id in the NEW rows (gone only if the
        // file dropped out of the result window).
        let selectedID: UInt32? = {
            guard let t = table, t.selectedRow >= 0, t.selectedRow < coord.parent.rows.count else { return nil }
            return coord.parent.rows[t.selectedRow].id
        }()
        coord.parent = self
        // Suppress the selection callback across reload+reselect: reloadData clears the
        // selection (a spurious "nothing selected") and the reselect below re-sets the
        // SAME file — neither is a user action, and firing onSelect here would mutate
        // published model state mid-view-update. Genuine clicks happen outside this.
        coord.suppressSelectionCallback = true
        defer { coord.suppressSelectionCallback = false }
        coord.updateRowHeight()
        table?.reloadData()
        if let id = selectedID, let t = table,
           let row = rows.firstIndex(where: { $0.id == id }) {
            t.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        coord.refreshPreview()
    }

    final class RenameTableView: NSTableView, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
        var renameSelected: (() -> Void)?
        var previewSelected: (() -> Void)?
        var previewURL: NSURL?
        weak var previewPanel: QLPreviewPanel?

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            previewPanel = panel
            panel.dataSource = self
            panel.delegate = self
        }
        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = nil
            panel.delegate = nil
            previewPanel = nil
        }
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            previewURL
        }
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard event.type == .keyDown else { return false }
            if event.keyCode == 49 || event.keyCode == 53 {
                panel.orderOut(nil)
                window?.makeFirstResponder(self)
                return true
            }
            if event.keyCode == 125 || event.keyCode == 126 {
                super.keyDown(with: event)
                return true
            }
            return false
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                previewSelected?()
            } else if (event.keyCode == 36 || event.keyCode == 76),
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                renameSelected?()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
        var parent: ResultsTable
        weak var table: NSTableView?
        weak var openWithMenu: NSMenu?
        var suppressSelectionCallback = false
        var editingRecord: FileRecord?
        var pendingParent: ResultsTable?
        private var editingField: NSTextField?
        private var savingRename = false
        init(_ p: ResultsTable) { parent = p }

        func updateRowHeight() {
            table?.rowHeight = max(17, ceil(NSFont.systemFont(ofSize: parent.fontSize).boundingRectForFont.height) + 2)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }

        @objc func ctxPreview() { if let table { showPreview(row: table.clickedRow, toggle: false) } }

        func showPreview(row: Int, toggle: Bool) {
            guard editingRecord == nil, let table = table as? RenameTableView,
                  parent.rows.indices.contains(row) else { return }
            if toggle, let panel = table.previewPanel, panel.isVisible {
                panel.orderOut(nil)
                table.window?.makeFirstResponder(table)
                return
            }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.previewURL = NSURL(fileURLWithPath: parent.rows[row].path)
            table.window?.makeFirstResponder(table)
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.updateController()
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }

        func refreshPreview() {
            guard let table = table as? RenameTableView,
                  let panel = table.previewPanel, panel.isVisible else { return }
            guard parent.rows.indices.contains(table.selectedRow) else {
                panel.orderOut(nil)
                table.previewURL = nil
                return
            }
            let url = NSURL(fileURLWithPath: parent.rows[table.selectedRow].path)
            if table.previewURL != url {
                table.previewURL = url
                panel.reloadData()
            }
        }

        @objc func ctxRename() { if let table { beginRename(row: table.clickedRow) } }

        func beginRename(row: Int) {
            guard editingRecord == nil, let table, parent.rows.indices.contains(row) else { return }
            let column = table.column(withIdentifier: .init("name"))
            guard column >= 0 else { return }
            table.scrollRowToVisible(row)
            table.scrollColumnToVisible(column)
            guard let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            editingRecord = parent.rows[row]
            editingField = field
            field.isEditable = true
            field.isSelectable = true
            field.delegate = self
            field.selectText(nil)
            if let editor = field.currentEditor() {
                let name = parent.rows[row].name
                let stem = parent.rows[row].isDir ? name : (name as NSString).deletingPathExtension
                editor.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                if !savingRename { finishRename() }
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                saveRename()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Leaving the editor cancels; only Return changes the filesystem.
            if !savingRename { finishRename(restoreTableFocus: false) }
        }

        private func saveRename() {
            guard !savingRename, let record = editingRecord, let field = editingField else { return }
            let name = field.stringValue
            savingRename = true
            field.isEditable = false
            // Return ends editing immediately, even if the filesystem operation is slow.
            // Restore focus here so completion cannot steal it from a later user click.
            if let table { table.window?.makeFirstResponder(table) }
            Task { @MainActor in
                do {
                    _ = try await Task.detached {
                        try FileRename.rename(path: record.path, to: name)
                    }.value
                    let notify = pendingParent?.onRenamed ?? parent.onRenamed
                    finishRename(restoreTableFocus: false)
                    if name != record.name { notify(record) }
                } catch {
                    finishRename(restoreTableFocus: false)
                    let alert = NSAlert(error: error)
                    alert.messageText = "Couldn’t rename “\(record.name)”"
                    if let window = table?.window { await alert.beginSheetModal(for: window) }
                    else { alert.runModal() }
                }
            }
        }

        private func finishRename(restoreTableFocus: Bool = true) {
            guard let record = editingRecord else { return }
            editingRecord = nil
            editingField?.delegate = nil
            editingField?.abortEditing()
            editingField?.stringValue = record.name
            editingField?.isEditable = false
            editingField?.isSelectable = false
            editingField = nil
            savingRename = false
            if let pendingParent { parent = pendingParent; self.pendingParent = nil }
            updateRowHeight()
            table?.reloadData()
            if let row = parent.rows.firstIndex(where: { $0.id == record.id }) {
                table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            if restoreTableFocus, let table {
                table.window?.makeFirstResponder(table)
            }
        }

        // Export an existing file URL so receiving apps can open the original file.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard parent.rows.indices.contains(row) else { return nil }
            let record = parent.rows[row]
            return NSURL(fileURLWithPath: record.path, isDirectory: record.isDir)
        }

        // Report the user's row pick up to the model so the menu bar can act on it.
        // Skipped during programmatic reselection (see updateNSView).
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionCallback, let t = table else { return }
            let r = t.selectedRow
            parent.onSelect(r >= 0 && r < parent.rows.count ? parent.rows[r] : nil)
            refreshPreview()
        }

        func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
            let rec = parent.rows[row]
            let key = col?.identifier.rawValue
            // Name column carries the file-type icon; everything else is text-only.
            if key == "name" {
                let cell = nameCell(t)
                cell.textField?.font = .systemFont(ofSize: parent.fontSize)
                cell.textField?.stringValue = rec.name
                cell.imageView?.image = FileIcons.icon(ext: Self.ext(rec.name), isDir: rec.isDir)
                return cell
            }
            let cell = textCell(t)
            cell.textField?.font = .systemFont(ofSize: parent.fontSize)
            switch key {
            case "path": cell.textField?.stringValue = rec.path
            case "size": cell.textField?.stringValue = rec.isDir ? "--" : ByteCountFormatter.string(fromByteCount: Int64(rec.size), countStyle: .file)
            case "kind": cell.textField?.stringValue = FileIcons.kind(ext: Self.ext(rec.name), isDir: rec.isDir)
            case "mtime": cell.textField?.stringValue = Self.df.string(from: Date(timeIntervalSince1970: TimeInterval(rec.mtime)))
            default: break
            }
            return cell
        }

        private static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }

        // Text-only reusable cell (path / size / kind / date columns).
        @MainActor private func textCell(_ t: NSTableView) -> NSTableCellView {
            let id = NSUserInterfaceItemIdentifier("cell")
            if let c = t.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return c }
            let c = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            c.textField = tf; c.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
            c.identifier = id
            return c
        }

        // Name cell: 16×16 icon on the left, name text after it.
        @MainActor private func nameCell(_ t: NSTableView) -> NSTableCellView {
            let id = NSUserInterfaceItemIdentifier("namecell")
            if let c = t.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return c }
            let c = NSTableCellView()
            let iv = NSImageView()
            iv.imageScaling = .scaleProportionallyUpOrDown
            let tf = NSTextField(labelWithString: "")
            c.imageView = iv; c.textField = tf
            c.addSubview(iv); c.addSubview(tf)
            iv.translatesAutoresizingMaskIntoConstraints = false
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                iv.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
            c.identifier = id
            return c
        }

        func tableView(_ t: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            guard let d = t.sortDescriptors.first, let k = d.key else { return }
            let key: QueryEngine.SortKey = ["name":.name,"path":.path,"size":.size,"kind":.kind,"mtime":.mtime][k] ?? .name
            parent.onSort(key, d.ascending)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let r = sender.clickedRow
            if r >= 0 && r < parent.rows.count { parent.onActivate(parent.rows[r]) }
        }

        // Context-menu handlers — resolve the right-clicked row, then delegate to ResultActions.
        private func clickedRecord() -> FileRecord? {
            guard let r = table?.clickedRow, r >= 0, r < parent.rows.count else { return nil }
            return parent.rows[r]
        }
        @objc func ctxOpen()     { if let r = clickedRecord() { ResultActions.open(r) } }
        @objc func ctxReveal()   { if let r = clickedRecord() { ResultActions.reveal(r) } }
        @objc func ctxCopyPath() { if let r = clickedRecord() { ResultActions.copyPath(r) } }
        @objc func ctxCopyName() { if let r = clickedRecord() { ResultActions.copyName(r) } }
        @objc func ctxTrash()    { if let r = clickedRecord() { ResultActions.trash(r) } }

        // Notepad Studio is always pinned in the submenu so any file — even one with
        // no associated app — can be opened with it. Resolved by bundle id at runtime
        // so it works wherever the app is installed (nil if not installed).
        private static let pinnedAppBundleID = "io.alesloas.notepad-studio"

        // Rebuild the "Open With" submenu for the right-clicked file just before it
        // shows: every app LaunchServices can open it with (icon + name, default
        // marked), then the pinned editor, then a "Choose Application…" picker — so
        // there's always something to open with. Chosen app rides on representedObject.
        func menuNeedsUpdate(_ menu: NSMenu) {
            guard menu === openWithMenu else { return }
            menu.removeAllItems()
            guard let rec = clickedRecord() else { return }
            let url = URL(fileURLWithPath: rec.path)
            let ws = NSWorkspace.shared
            var apps = ws.urlsForApplications(toOpen: url)
            let defaultApp = ws.urlForApplication(toOpen: url)

            // Pin Notepad Studio if it isn't already in the associated list.
            if let pinned = ws.urlForApplication(withBundleIdentifier: Self.pinnedAppBundleID),
               !apps.contains(where: { $0.standardizedFileURL == pinned.standardizedFileURL }) {
                apps.append(pinned)
            }

            for app in apps {
                var name = FileManager.default.displayName(atPath: app.path)
                if app.standardizedFileURL == defaultApp?.standardizedFileURL { name += " (default)" }
                let item = NSMenuItem(title: name, action: #selector(ctxOpenWith(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app
                let icon = ws.icon(forFile: app.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }

            menu.addItem(.separator())
            let choose = NSMenuItem(title: "Choose Application…", action: #selector(ctxOpenWithChoose), keyEquivalent: "")
            choose.target = self
            menu.addItem(choose)
        }

        @objc func ctxOpenWith(_ sender: NSMenuItem) {
            guard let r = clickedRecord(), let app = sender.representedObject as? URL else { return }
            ResultActions.open(r, with: app)
        }

        // Browse for any app to open the file with (Finder's "Open With ▸ Other…").
        // Capture the record first — runModal blocks, but clickedRow stays valid.
        @objc func ctxOpenWithChoose() {
            guard let r = clickedRecord() else { return }
            let panel = NSOpenPanel()
            panel.title = "Choose Application"
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let app = panel.url {
                ResultActions.open(r, with: app)
            }
        }

        static let df: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    }
}
