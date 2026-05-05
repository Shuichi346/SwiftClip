import AppKit

enum SnippetsMenuSection {
    @MainActor
    static func add(to menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        addFlatSnippetSection(to: menu, environment: environment, target: target)
    }

    @MainActor
    static func addStandalone(to menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        addFlatSnippetSection(to: menu, environment: environment, target: target)
    }

    @MainActor
    private static func addFlatSnippetSection(
        to menu: NSMenu,
        environment: AppEnvironment,
        target: StatusItemController
    ) {
        let headerItem = NSMenuItem(title: L10n.string("menubar.snippets"), action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let folders = environment.snippets.enabledFolders()
        if folders.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("snippets.empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for folder in folders {
            menu.addItem(folderItem(for: folder, environment: environment, target: target))
        }
    }

    @MainActor
    private static func folderItem(
        for folder: SnippetSummary,
        environment: AppEnvironment,
        target: StatusItemController
    ) -> NSMenuItem {
        let folderMenu = NSMenu(title: folder.title)

        if folder.snippets.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("snippets.folderEmpty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            folderMenu.addItem(emptyItem)
        } else {
            for snippet in folder.snippets {
                let item = NSMenuItem(
                    title: snippet.title.swiftClipTruncated(to: environment.preferences.state.menuTitleCharacterLimit),
                    action: #selector(StatusItemController.selectSnippetItem(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = SnippetMenuPayload(folderID: folder.id, snippetID: snippet.id)
                item.toolTip = snippet.content.isEmpty ? nil : snippet.content
                folderMenu.addItem(item)
            }
        }

        let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
        folderItem.submenu = folderMenu
        return folderItem
    }
}
