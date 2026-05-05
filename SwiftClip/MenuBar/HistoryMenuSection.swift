import AppKit

enum HistoryMenuSection {
    @MainActor
    static func add(to menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        let submenu = NSMenu(title: L10n.string("menubar.history"))

        if environment.history.items.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.string("history.empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for (index, item) in environment.history.items.enumerated() {
                let menuItem = NSMenuItem(
                    title: item.menuTitle(index: index, preferences: environment.preferences.state),
                    action: #selector(StatusItemController.selectHistoryItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = target
                menuItem.representedObject = item.id
                submenu.addItem(menuItem)
            }
        }

        let rootItem = NSMenuItem(title: L10n.string("menubar.history"), action: nil, keyEquivalent: "")
        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }
}
