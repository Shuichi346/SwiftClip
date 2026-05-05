import AppKit

enum SnippetsMenuSection {
    @MainActor
    static func add(to menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        let submenu = NSMenu(title: L10n.string("menubar.snippets"))
        let folders = environment.snippets.enabledFolders()

        if folders.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("snippets.empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for folder in folders {
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
                        folderMenu.addItem(item)
                    }
                }

                let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
                folderItem.submenu = folderMenu
                submenu.addItem(folderItem)
            }
        }

        let rootItem = NSMenuItem(title: L10n.string("menubar.snippets"), action: nil, keyEquivalent: "")
        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }
}
