import SwiftUI

struct GeneralTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle(
                L10n.string("prefs.general.launchAtLogin"),
                isOn: Binding {
                    preferences.state.launchAtLogin
                } set: { enabled in
                    preferences.setLaunchAtLogin(enabled)
                }
            )

            Toggle(
                L10n.string("prefs.general.pasteAfterSelection"),
                isOn: preferences.binding(\.pasteAfterSelection)
            )

            Stepper(
                value: preferences.binding(\.historyLimit),
                in: 1...PreferencesState.maximumHistoryLimit
            ) {
                Text(
                    String(
                        format: L10n.string("prefs.general.historyLimit"),
                        preferences.state.historyLimit
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
