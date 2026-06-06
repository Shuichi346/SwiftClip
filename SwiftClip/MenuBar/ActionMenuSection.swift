import AppKit

enum ActionMenuSection {
    @MainActor
    static func add(to menu: NSMenu, target: StatusItemController, showsQuitShortcut: Bool = true) {
        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: L10n.string("menubar.clearHistory"),
            action: #selector(StatusItemController.clearHistory(_:)),
            keyEquivalent: ""
        )
        clearItem.target = target
        menu.addItem(clearItem)

        let editorItem = NSMenuItem(
            title: L10n.string("menubar.editSnippets"),
            action: #selector(StatusItemController.openSnippetEditor(_:)),
            keyEquivalent: ""
        )
        editorItem.target = target
        menu.addItem(editorItem)

        let preferencesItem = NSMenuItem(
            title: L10n.string("menubar.preferences"),
            action: #selector(StatusItemController.openPreferences(_:)),
            keyEquivalent: ""
        )
        preferencesItem.target = target
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menubar.quit"),
            action: #selector(StatusItemController.quit(_:)),
            keyEquivalent: showsQuitShortcut ? "q" : ""
        )
        quitItem.target = target
        menu.addItem(quitItem)
    }
}
