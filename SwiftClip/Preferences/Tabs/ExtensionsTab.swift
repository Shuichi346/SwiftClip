import KeyboardShortcuts
import SwiftUI

struct ExtensionsTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(L10n.string("prefs.extensions.plainTextPaste"), name: .plainTextPaste)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
