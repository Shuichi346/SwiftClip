import KeyboardShortcuts
import SwiftUI

struct ExtensionsTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle(
                L10n.string("prefs.extensions.deleteOnSelect"),
                isOn: preferences.binding(\.deleteOnSelect)
            )

            Toggle(
                L10n.string("prefs.extensions.deleteAfterPaste"),
                isOn: preferences.binding(\.deleteAfterPaste)
            )

            KeyboardShortcuts.Recorder(L10n.string("prefs.extensions.plainTextPaste"), name: .plainTextPaste)
            KeyboardShortcuts.Recorder(L10n.string("prefs.extensions.deleteOnSelectShortcut"), name: .deleteOnSelect)
            KeyboardShortcuts.Recorder(L10n.string("prefs.extensions.deleteAfterPasteShortcut"), name: .deleteAfterPaste)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
