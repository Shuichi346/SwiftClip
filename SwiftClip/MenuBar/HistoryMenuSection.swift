import AppKit

enum HistoryMenuSection {
    private static let standaloneRangeSize = 5

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

    @MainActor
    static func addStandalone(to menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        let headerItem = NSMenuItem(title: L10n.string("menubar.history"), action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        guard !environment.history.items.isEmpty else {
            let emptyItem = NSMenuItem(title: L10n.string("history.empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let items = environment.history.items
        let preferences = environment.preferences.state

        for rangeStart in stride(from: 0, to: items.count, by: standaloneRangeSize) {
            let rangeEnd = min(rangeStart + standaloneRangeSize, items.count)
            let title = rangeTitle(startIndex: rangeStart, endIndex: rangeEnd - 1, preferences: preferences)
            let submenu = NSMenu(title: title)

            for index in rangeStart..<rangeEnd {
                let historyItem = items[index]
                let menuItem = NSMenuItem(
                    title: historyItem.menuTitle(index: index, preferences: preferences),
                    action: #selector(StatusItemController.selectHistoryItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = target
                menuItem.representedObject = historyItem.id
                submenu.addItem(menuItem)
            }

            let rangeItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            rangeItem.submenu = submenu
            menu.addItem(rangeItem)
        }
    }

    private static func rangeTitle(startIndex: Int, endIndex: Int, preferences: PreferencesState) -> String {
        let start = displayedIndex(for: startIndex, preferences: preferences)
        let end = displayedIndex(for: endIndex, preferences: preferences)
        return "\(start) - \(end)"
    }

    private static func displayedIndex(for index: Int, preferences: PreferencesState) -> Int {
        preferences.startNumbersAtZero ? index : index + 1
    }
}
