import AppKit
import Combine

private final class MetricTableView: NSTableView {
    var moveSelection: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), event.keyCode == 126 || event.keyCode == 125 {
            moveSelection?(event.keyCode == 126 ? -1 : 1)
        } else { super.keyDown(with: event) }
    }
}

private final class MetricDragHandle: NSImageView {
    var startDrag: ((NSEvent) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { startDrag?(event) }
}

final class MenuBarSettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: MonitorModel
    private let table = MetricTableView()
    private let preview = MeterView(frame: .zero)
    private let previewLabel = NSTextField(labelWithString: "")
    private let sectionLabel = NSTextField(labelWithString: "")
    private let helpLabel = NSTextField(labelWithString: "")
    private let savedLabel = NSTextField(labelWithString: "")
    private let memoryFormat = NSPopUpButton()
    private let networkFormat = NSPopUpButton()
    private let memoryLabel = NSTextField(labelWithString: "")
    private let networkLabel = NSTextField(labelWithString: "")
    private let privacy = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let restore = NSButton()
    private var subscriptions = Set<AnyCancellable>()
    private var selectedMetric: MenuBarMetric?
    private static let dragType = NSPasteboard.PasteboardType("io.github.chenmobuys.Neylu.menuBarMetric")

    init(model: MonitorModel) {
        self.model = model
        let window = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        preview.setAccessibilityElement(true)
        preview.setAccessibilityRole(.image)
        window.isReleasedWhenClosed = false
        window.title = L("menu_bar.title")
        window.identifier = NSUserInterfaceItemIdentifier("menuBarSettings")
        let surface = NSVisualEffectView()
        surface.material = .windowBackground
        surface.blendingMode = .behindWindow
        surface.state = .followsWindowActiveState
        window.contentView = surface
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16)
        ])
        for label in [previewLabel, sectionLabel, helpLabel, savedLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        stack.addArrangedSubview(previewLabel)
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 6
        box.contentViewMargins = NSSize(width: 10, height: 10)
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        box.heightAnchor.constraint(equalToConstant: 48).isActive = true
        if let content = box.contentView {
            content.addSubview(preview)
            preview.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        }
        for (label, control, tag) in [(memoryLabel, memoryFormat, 0), (networkLabel, networkFormat, 1)] {
            control.tag = tag; control.target = self; control.action = #selector(changeFormat(_:))
            let row = NSStackView(views: [label, NSView(), control])
            row.orientation = .horizontal
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        privacy.target = self; privacy.action = #selector(togglePrivacy)
        stack.addArrangedSubview(privacy)
        stack.addArrangedSubview(sectionLabel)
        table.headerView = nil
        table.style = .inset
        table.selectionHighlightStyle = .none
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = .separatorColor
        table.backgroundColor = .controlBackgroundColor
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("metric"))
        column.width = 340
        table.addTableColumn(column)
        table.delegate = self
        table.dataSource = self
        table.registerForDraggedTypes([Self.dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setAccessibilityLabel(L("menu_bar.visible_metrics"))
        table.moveSelection = { [weak self] in self?.moveSelected(by: $0) }
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = table
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 236).isActive = true
        let footer = NSStackView(views: [helpLabel, NSView(), savedLabel])
        footer.orientation = .horizontal
        footer.distribution = .fill
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        restore.target = self; restore.action = #selector(restoreLayout)
        restore.bezelStyle = .rounded
        stack.addArrangedSubview(restore)
        refreshControls()
        window.setContentSize(NSSize(width: 380, height: surface.fittingSize.height))
        window.center()
        model.$reading.sink { [weak self] reading in
            guard let self, self.window?.isVisible == true else { return }
            self.preview.reading = reading
            self.preview.setAccessibilityLabel(self.preview.accessibilitySummary)
        }.store(in: &subscriptions)
        model.settings.$menuBarConfiguration.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshControls() }
        }.store(in: &subscriptions)
        model.settings.$menuBarFormats.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPreview() }
        }.store(in: &subscriptions)
        model.settings.$hideNetworkAddress.dropFirst().sink { [weak self] hidden in
            DispatchQueue.main.async { self?.privacy.state = hidden ? .on : .off }
        }.store(in: &subscriptions)
        model.settings.$basis.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPreview() }
        }.store(in: &subscriptions)
        model.settings.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshControls() }
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refreshControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func refreshPreview() {
        preview.reading = model.reading
        window?.contentView?.layoutSubtreeIfNeeded()
        preview.basis = model.basis
        preview.formats = model.settings.menuBarFormats
        preview.configuration = model.settings.menuBarConfiguration
        let width = MeterView.meterWidth(for: model.basis, configuration: preview.configuration, formats: preview.formats)
        if let parent = preview.superview {
            preview.frame = NSRect(x: max(0, parent.bounds.width - width), y: (parent.bounds.height - 22) / 2, width: width, height: 22)
        }
        preview.needsDisplay = true
        preview.setAccessibilityLabel(preview.accessibilitySummary)
    }
    private func refreshControls() {
        window?.title = L("menu_bar.title")
        memoryLabel.stringValue = L("format.memory")
        networkLabel.stringValue = L("format.network")
        memoryFormat.removeAllItems(); memoryFormat.addItems(withTitles: [L("format.percent"), L("format.capacity")])
        networkFormat.removeAllItems(); networkFormat.addItems(withTitles: [L("format.bytes"), L("format.bits")])
        memoryFormat.selectItem(at: model.settings.menuBarFormats.memoryCapacity ? 1 : 0)
        networkFormat.selectItem(at: model.settings.menuBarFormats.networkBits ? 1 : 0)
        memoryFormat.setAccessibilityLabel(L("format.memory")); networkFormat.setAccessibilityLabel(L("format.network"))
        privacy.title = L("privacy.hide_address"); privacy.state = model.settings.hideNetworkAddress ? .on : .off
        restore.title = L("menu_bar.restore_layout")
        restore.isEnabled = model.settings.menuBarConfiguration != .defaults
        previewLabel.stringValue = L("menu_bar.preview")
        sectionLabel.stringValue = L("menu_bar.visible_metrics")
        helpLabel.stringValue = L("menu_bar.drag_to_reorder") + " · ⌥↑↓"
        savedLabel.stringValue = L("menu_bar.applied_immediately")
        table.setAccessibilityLabel(L("menu_bar.visible_metrics"))
        let selection = selectedMetric
        table.reloadData()
        table.sizeLastColumnToFit()
        selectedMetric = selection
        if let metric = selection, let row = model.settings.menuBarConfiguration.items.firstIndex(where: { $0.metric == metric }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshPreview()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model.settings.menuBarConfiguration.items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = model.settings.menuBarConfiguration.items[row]
        let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleMetric(_:)))
        check.identifier = NSUserInterfaceItemIdentifier(item.metric.rawValue)
        check.state = item.enabled ? .on : .off
        check.setAccessibilityLabel(String(format: L("menu_bar.show_metric_format"), item.metric.title))
        let icon = NSImageView(image: NSImage(systemSymbolName: item.metric.symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))!)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let title = NSTextField(labelWithString: item.metric.title)
        title.font = .systemFont(ofSize: 13)
        let labels = NSStackView(views: [title])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        if item.metric == .network {
            let subtitle = NSTextField(labelWithString: L("menu_bar.network_detail"))
            subtitle.font = .systemFont(ofSize: 10.5)
            subtitle.textColor = .secondaryLabelColor
            labels.addArrangedSubview(subtitle)
        }
        let handle = MetricDragHandle(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L("menu_bar.drag_to_reorder"))!)
        handle.contentTintColor = .tertiaryLabelColor
        handle.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let cell = NSTableCellView()
        let stack = NSStackView(views: [check, icon, labels, NSView(), handle])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        handle.startDrag = { [weak self, weak cell, weak handle] event in
            guard let self, let cell, let handle,
                  let currentRow = self.model.settings.menuBarConfiguration.items.firstIndex(where: { $0.metric == item.metric }),
                  let writer = self.tableView(self.table, pasteboardWriterForRow: currentRow),
                  let bitmap = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) else { return }
            self.selectedMetric = item.metric
            self.table.selectRowIndexes(IndexSet(integer: currentRow), byExtendingSelection: false)
            cell.cacheDisplay(in: cell.bounds, to: bitmap)
            let image = NSImage(size: cell.bounds.size)
            image.addRepresentation(bitmap)
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(handle.convert(cell.bounds, from: cell), contents: image)
            handle.beginDraggingSession(with: [draggingItem], event: event, source: self.table)
        }
        return cell
    }
    @objc private func changeFormat(_ sender: NSPopUpButton) {
        if sender.tag == 0 { model.settings.menuBarFormats.memoryCapacity = sender.indexOfSelectedItem == 1 }
        else { model.settings.menuBarFormats.networkBits = sender.indexOfSelectedItem == 1 }
    }
    @objc private func togglePrivacy() { model.settings.hideNetworkAddress = privacy.state == .on }
    @objc private func restoreLayout() {
        selectedMetric = nil; table.deselectAll(nil)
        model.settings.restoreMenuBarLayout()
    }
    @objc private func toggleMetric(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let metric = MenuBarMetric(rawValue: id) else { return }
        model.settings.menuBarConfiguration.setEnabled(sender.state == .on, for: metric)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if model.settings.menuBarConfiguration.items.indices.contains(row) {
            selectedMetric = model.settings.menuBarConfiguration.items[row].metric
        }
    }
    private func moveSelected(by delta: Int) {
        guard let metric = selectedMetric,
              let row = model.settings.menuBarConfiguration.items.firstIndex(where: { $0.metric == metric }),
              model.settings.menuBarConfiguration.items.indices.contains(row + delta) else { return }
        model.settings.menuBarConfiguration.move(metric, to: delta > 0 ? row + 2 : row - 1)
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(model.settings.menuBarConfiguration.items[row].metric.rawValue, forType: Self.dragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard (info.draggingSource as? NSTableView) === tableView, (0...numberOfRows(in: tableView)).contains(row) else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard (info.draggingSource as? NSTableView) === tableView, operation == .above,
              let raw = info.draggingPasteboard.string(forType: Self.dragType), let metric = MenuBarMetric(rawValue: raw) else { return false }
        selectedMetric = metric
        model.settings.menuBarConfiguration.move(metric, to: row)
        return true
    }
}
