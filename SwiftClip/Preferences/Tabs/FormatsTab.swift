import SwiftUI

struct FormatsTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle(L10n.string("prefs.formats.plainText"), isOn: preferences.binding(\.formatPlainText))
            Toggle(L10n.string("prefs.formats.rtf"), isOn: preferences.binding(\.formatRTF))
            Toggle(L10n.string("prefs.formats.rtfd"), isOn: preferences.binding(\.formatRTFD))
            Toggle(L10n.string("prefs.formats.fileURL"), isOn: preferences.binding(\.formatFileURL))
            Toggle(L10n.string("prefs.formats.url"), isOn: preferences.binding(\.formatURL))
            Toggle(L10n.string("prefs.formats.pdf"), isOn: preferences.binding(\.formatPDF))
            Toggle(L10n.string("prefs.formats.image"), isOn: preferences.binding(\.formatImage))
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
