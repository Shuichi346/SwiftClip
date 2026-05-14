import SwiftUI

struct PreferencesWindow: View {
    @ObservedObject private var preferences: PreferencesStore

    init(environment: AppEnvironment) {
        _preferences = ObservedObject(wrappedValue: environment.preferences)
    }

    var body: some View {
        TabView {
            GeneralTab(preferences: preferences)
                .tabItem {
                    Label(L10n.string("prefs.tab.general"), systemImage: "gearshape")
                }

            MenuTab(preferences: preferences)
                .tabItem {
                    Label(L10n.string("prefs.tab.menu"), systemImage: "menucard")
                }

            FormatsTab(preferences: preferences)
                .tabItem {
                    Label(L10n.string("prefs.tab.formats"), systemImage: "doc.on.clipboard")
                }

            ExcludedAppsTab(preferences: preferences)
                .tabItem {
                    Label(L10n.string("prefs.tab.apps"), systemImage: "nosign.app")
                }

            ShortcutsTab()
                .tabItem {
                    Label(L10n.string("prefs.tab.shortcuts"), systemImage: "keyboard")
                }

            ExtensionsTab(preferences: preferences)
                .tabItem {
                    Label(L10n.string("prefs.tab.extensions"), systemImage: "puzzlepiece.extension")
                }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 460)
    }
}
