import AppKit

enum MainMenuBuilder {
    @MainActor
    static func populate(menu: NSMenu, environment: AppEnvironment, target: StatusItemController) {
        menu.removeAllItems()

        HistoryMenuSection.add(to: menu, environment: environment, target: target)
        menu.addItem(.separator())
        SnippetsMenuSection.add(to: menu, environment: environment, target: target)
        ActionMenuSection.add(to: menu, target: target)
    }
}
