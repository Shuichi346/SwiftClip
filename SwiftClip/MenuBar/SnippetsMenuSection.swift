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
    static func populateFolderPopup(
        menu: NSMenu,
        folder: SnippetSummary,
        environment: AppEnvironment,
        target: StatusItemController
    ) {
        menu.removeAllItems()

        let headerItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        addSnippetItems(
            folder: folder,
            to: menu,
            environment: environment,
            target: target
        )
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

        addSnippetItems(
            folder: folder,
            to: folderMenu,
            environment: environment,
            target: target
        )

        let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
        folderItem.submenu = folderMenu
        return folderItem
    }

    @MainActor
    private static func addSnippetItems(
        folder: SnippetSummary,
        to folderMenu: NSMenu,
        environment: AppEnvironment,
        target: StatusItemController
    ) {
        let snippets = folder.snippets.filter(\.isEnabled)
        if snippets.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("snippets.folderEmpty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            folderMenu.addItem(emptyItem)
        } else {
            for snippet in snippets {
                let item = NSMenuItem(
                    title: snippet.title.swiftClipTruncated(to: environment.preferences.state.menuTitleCharacterLimit),
                    action: #selector(StatusItemController.selectSnippetItem(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = SnippetMenuPayload(folderID: folder.id, snippetID: snippet.id)
                item.toolTip = tooltip(for: snippet)
                folderMenu.addItem(item)
            }
        }
    }

    static func tooltip(for snippet: SnippetLeaf) -> String? {
        let contentLimit = 240
        let attachmentNameLimit = 60
        let attachmentCountLimit = 5
        var parts: [String] = []
        if !snippet.content.isEmpty {
            parts.append(snippet.content.swiftClipTruncated(to: contentLimit))
        }

        let attachmentNames = snippet.attachmentURLs
            .compactMap(URL.init(string:))
            .map(\.lastPathComponent)
            .filter { !$0.isEmpty }

        if !attachmentNames.isEmpty {
            let visibleNames = attachmentNames.prefix(attachmentCountLimit).map {
                $0.swiftClipTruncated(to: attachmentNameLimit)
            }
            let hiddenCount = attachmentNames.count - visibleNames.count
            let suffix = hiddenCount > 0 ? ", +\(hiddenCount)" : ""
            parts.append(visibleNames.joined(separator: ", ") + suffix)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
