import SwiftUI

struct MenuTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Toggle(
                L10n.string("prefs.menu.showNumbers"),
                isOn: preferences.binding(\.showNumbers)
            )

            Toggle(
                L10n.string("prefs.menu.startAtZero"),
                isOn: preferences.binding(\.startNumbersAtZero)
            )

            Stepper(
                value: preferences.binding(\.menuTitleCharacterLimit),
                in: 5...120
            ) {
                Text(
                    String(
                        format: L10n.string("prefs.menu.titleLimit"),
                        preferences.state.menuTitleCharacterLimit
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
