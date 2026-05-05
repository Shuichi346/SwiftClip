import KeyboardShortcuts
import SwiftUI

struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(L10n.string("shortcuts.mainMenu"), name: .mainMenu)
            KeyboardShortcuts.Recorder(L10n.string("shortcuts.clearHistory"), name: .clearHistory)
            KeyboardShortcuts.Recorder(L10n.string("shortcuts.snippetEditor"), name: .snippetEditor)
            KeyboardShortcuts.Recorder(L10n.string("shortcuts.preferences"), name: .preferences)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
