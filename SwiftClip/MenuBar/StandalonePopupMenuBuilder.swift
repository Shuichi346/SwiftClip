import AppKit

enum StandalonePopupMenuBuilder {
    @MainActor
    static func populate(menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        menu.removeAllItems()

        HistoryMenuSection.addStandalone(to: menu, environment: environment, target: target)
        menu.addItem(.separator())
        SnippetsMenuSection.addStandalone(to: menu, environment: environment, target: target)
        ActionMenuSection.add(to: menu, target: target)
    }
}
