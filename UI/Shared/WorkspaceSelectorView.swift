import AppKit

final class WorkspaceSelectorView: NSView, NSTextFieldDelegate {
    private enum Choice {
        case workspace(UUID)
        case create
        case rename
    }

    private struct MoveDestination {
        let sessionID: UUID
        let workspaceID: UUID
    }

    private let documentStore: DocumentStore
    private let windowID: UUID
    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var nameSubmitButton: NSButton?

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(frame: .zero)

        popUpButton.isBordered = false
        popUpButton.controlSize = .small
        popUpButton.font = .systemFont(ofSize: 11, weight: .medium)
        popUpButton.cell?.lineBreakMode = .byTruncatingTail
        popUpButton.target = self
        popUpButton.action = #selector(handleSelection)
        popUpButton.identifier = NSUserInterfaceItemIdentifier("workspaceSelector")
        popUpButton.setAccessibilityLabel(L10n.text("Workspace", "工作区"))
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
        popUpButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(popUpButton)
        NSLayoutConstraint.activate([
            popUpButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            popUpButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            popUpButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: min(max(popUpButton.intrinsicContentSize.width, 86), 160), height: 24)
    }

    func refresh() {
        let workspaces = documentStore.workspaces(in: windowID)
        let activeID = documentStore.activeWorkspaceID(in: windowID)
        let menu = NSMenu()
        menu.autoenablesItems = false
        var selectedItem: NSMenuItem?
        for workspace in workspaces {
            let item = NSMenuItem(title: workspace.name, action: nil, keyEquivalent: "")
            item.representedObject = Choice.workspace(workspace.id)
            item.state = workspace.id == activeID ? .on : .off
            menu.addItem(item)
            if workspace.id == activeID {
                selectedItem = item
                popUpButton.toolTip = workspace.name
            }
        }
        menu.addItem(.separator())
        let createItem = NSMenuItem(title: L10n.text("New Workspace…", "新建工作区…"), action: nil, keyEquivalent: "")
        createItem.representedObject = Choice.create
        menu.addItem(createItem)
        let renameItem = NSMenuItem(title: L10n.text("Rename Workspace…", "重命名工作区…"), action: nil, keyEquivalent: "")
        renameItem.representedObject = Choice.rename
        renameItem.isEnabled = activeID != nil
        menu.addItem(renameItem)
        popUpButton.menu = menu
        popUpButton.select(selectedItem)
        invalidateIntrinsicContentSize()
        refreshChromeColors()
    }

    func refreshChromeColors() {
        popUpButton.contentTintColor = NightModeStyle.secondaryTextColor
    }

    @objc private func handleSelection() {
        guard let choice = popUpButton.selectedItem?.representedObject as? Choice else { return }
        switch choice {
        case .workspace(let id):
            documentStore.activateWorkspace(id, in: windowID)
            refresh()
        case .create:
            refresh()
            presentNameEditor(workspaceID: nil)
        case .rename:
            refresh()
            if let id = documentStore.activeWorkspaceID(in: windowID) {
                presentNameEditor(workspaceID: id)
            }
        }
    }

    private func presentNameEditor(workspaceID: UUID?) {
        guard let window else { return }
        let workspaces = documentStore.workspaces(in: windowID)
        let currentName = workspaces.first { $0.id == workspaceID }?.name
        var nextNumber = workspaces.count + 1
        while workspaces.contains(where: { $0.name == L10n.text("Workspace \(nextNumber)", "工作区 \(nextNumber)") }) {
            nextNumber += 1
        }

        let alert = NSAlert()
        alert.messageText = workspaceID == nil ? L10n.text("New Workspace", "新建工作区") : L10n.text("Rename Workspace", "重命名工作区")
        alert.addButton(withTitle: workspaceID == nil ? L10n.text("Create", "创建") : L10n.text("Rename", "重命名"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        let field = NSTextField(string: currentName ?? L10n.text("Workspace \(nextNumber)", "工作区 \(nextNumber)"))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.setAccessibilityLabel(L10n.text("Workspace name", "工作区名称"))
        field.delegate = self
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        nameSubmitButton = alert.buttons.first
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.nameSubmitButton = nil
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            if let workspaceID {
                self.documentStore.renameWorkspace(workspaceID, name: name, in: self.windowID)
            } else {
                self.documentStore.createWorkspace(name: name, in: self.windowID)
            }
            self.refresh()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        nameSubmitButton?.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func moveMenu(for sessionID: UUID) -> NSMenu? {
        guard let session = documentStore.session(for: sessionID), !session.isBlank else { return nil }
        let activeID = documentStore.activeWorkspaceID(in: windowID)
        let destinations = documentStore.workspaces(in: windowID).filter { $0.id != activeID }
        guard !destinations.isEmpty else { return nil }
        let menu = NSMenu()
        for workspace in destinations {
            let item = NSMenuItem(title: workspace.name, action: #selector(moveDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MoveDestination(sessionID: sessionID, workspaceID: workspace.id)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func moveDocument(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? MoveDestination else { return }
        documentStore.moveSession(destination.sessionID, toWorkspace: destination.workspaceID, in: windowID)
    }
}
