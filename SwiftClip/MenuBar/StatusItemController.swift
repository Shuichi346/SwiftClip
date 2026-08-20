import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var isMenuDirty = true
    private var cancellables: Set<AnyCancellable> = []

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "SwiftClip"
            )
            button.image?.isTemplate = true
        }

        menu.delegate = self
        statusItem.menu = menu
        observeMenuChanges()
        rebuildMenuIfNeeded()
    }

    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    func showStandalonePopupAtCursor() {
        let popupMenu = NSMenu()
        StandalonePopupMenuBuilder.populate(menu: popupMenu, environment: environment, target: self)

        popUpAtCursor(popupMenu)
    }

    func showSnippetFolderPopupAtCursor(folderID: UUID) {
        guard let folder = environment.snippets.folder(id: folderID),
              folder.isEnabled else {
            return
        }

        let popupMenu = NSMenu(title: folder.title)
        SnippetsMenuSection.populateFolderPopup(
            menu: popupMenu,
            folder: folder,
            environment: environment,
            target: self
        )
        popUpAtCursor(popupMenu)
    }

    private func popUpAtCursor(_ popupMenu: NSMenu) {
        let cursorLocation = NSEvent.mouseLocation
        let popupLocation = NSPoint(x: cursorLocation.x + 6, y: cursorLocation.y - 6)
        popupMenu.popUp(positioning: nil, at: popupLocation, in: nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenuIfNeeded()
    }

    @objc func selectHistoryItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = environment.history.item(id: id) else {
            return
        }

        environment.pasteEngine.paste(item: item)
    }

    @objc func selectSnippetItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SnippetMenuPayload,
              let snippet = environment.snippets.snippet(folderID: payload.folderID, snippetID: payload.snippetID) else {
            return
        }

        environment.pasteEngine.paste(snippet: snippet)
    }

    @objc func clearHistory(_ sender: NSMenuItem) {
        environment.history.clearAll()
    }

    @objc func openSnippetEditor(_ sender: NSMenuItem) {
        environment.openSnippetEditor?()
    }

    @objc func openPreferences(_ sender: NSMenuItem) {
        environment.openPreferences?()
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func observeMenuChanges() {
        environment.history.$items
            .sink { [weak self] _ in
                self?.isMenuDirty = true
            }
            .store(in: &cancellables)
        environment.snippets.$folders
            .sink { [weak self] _ in
                self?.isMenuDirty = true
            }
            .store(in: &cancellables)
        environment.preferences.$state
            .sink { [weak self] _ in
                self?.isMenuDirty = true
            }
            .store(in: &cancellables)
    }

    private func rebuildMenuIfNeeded() {
        guard isMenuDirty else {
            return
        }

        MainMenuBuilder.populate(menu: menu, environment: environment, target: self)
        isMenuDirty = false
    }
}

struct SnippetMenuPayload {
    var folderID: UUID
    var snippetID: UUID
}
