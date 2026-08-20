import SwiftUI

struct GeneralTab: View {
    @ObservedObject var preferences: PreferencesStore
    var openPermissions: () -> Void
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Toggle(
                L10n.string("prefs.general.launchAtLogin"),
                isOn: Binding {
                    preferences.state.launchAtLogin
                } set: { enabled in
                    do {
                        try preferences.setLaunchAtLogin(enabled)
                    } catch {
                        launchAtLoginError = error.localizedDescription
                    }
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

            Button(L10n.string("prefs.general.openPermissions")) {
                openPermissions()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .alert(
            L10n.string("prefs.general.launchAtLoginError"),
            isPresented: Binding {
                launchAtLoginError != nil
            } set: { isPresented in
                if !isPresented {
                    launchAtLoginError = nil
                }
            }
        ) {
            Button(L10n.string("alert.ok"), role: .cancel) {}
        } message: {
            Text(launchAtLoginError ?? "")
        }
    }
}
