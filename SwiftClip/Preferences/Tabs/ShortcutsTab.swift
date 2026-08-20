import KeyboardShortcuts
import SwiftUI

struct ShortcutsTab: View {
    var body: some View {
        Form {
            SwiftClipShortcutRecorder(title: L10n.string("shortcuts.mainMenu"), name: .mainMenu)
            SwiftClipShortcutRecorder(title: L10n.string("shortcuts.clearHistory"), name: .clearHistory)
            SwiftClipShortcutRecorder(title: L10n.string("shortcuts.snippetEditor"), name: .snippetEditor)
            SwiftClipShortcutRecorder(title: L10n.string("shortcuts.preferences"), name: .preferences)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
