import SwiftUI

struct ExtensionsTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle(
                L10n.string("prefs.extensions.alwaysPasteAsPlainText"),
                isOn: preferences.binding(\.alwaysPasteAsPlainText)
            )
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
