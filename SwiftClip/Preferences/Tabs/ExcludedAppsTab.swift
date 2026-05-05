import SwiftUI

struct ExcludedAppsTab: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(L10n.string("prefs.excluded.placeholder"), text: $newBundleID)
                    .textFieldStyle(.roundedBorder)

                Button {
                    preferences.addExcludedBundleID(newBundleID)
                    newBundleID = ""
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.string("prefs.excluded.add"))
            }

            List {
                ForEach(preferences.state.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            preferences.removeExcludedBundleID(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("prefs.excluded.remove"))
                    }
                }
            }
        }
        .padding(20)
    }
}
