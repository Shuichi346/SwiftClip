import SwiftUI

struct ExcludedAppsTab: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var newExcludedBundleID = ""
    @State private var newMixedSnippetPasteBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            bundleIDSection(
                title: L10n.string("prefs.excluded.title"),
                helper: L10n.string("prefs.excluded.helper"),
                placeholder: L10n.string("prefs.excluded.placeholder"),
                addHelp: L10n.string("prefs.excluded.add"),
                removeHelp: L10n.string("prefs.excluded.remove"),
                bundleIDs: preferences.state.excludedBundleIDs,
                newBundleID: $newExcludedBundleID,
                add: preferences.addExcludedBundleID,
                remove: preferences.removeExcludedBundleID
            )

            Divider()

            bundleIDSection(
                title: L10n.string("prefs.mixedPaste.title"),
                helper: L10n.string("prefs.mixedPaste.helper"),
                placeholder: L10n.string("prefs.mixedPaste.placeholder"),
                addHelp: L10n.string("prefs.mixedPaste.add"),
                removeHelp: L10n.string("prefs.mixedPaste.remove"),
                bundleIDs: preferences.state.mixedSnippetPasteBundleIDs,
                newBundleID: $newMixedSnippetPasteBundleID,
                add: preferences.addMixedSnippetPasteBundleID,
                remove: preferences.removeMixedSnippetPasteBundleID
            )
        }
        .padding(20)
    }

    private func bundleIDSection(
        title: String,
        helper: String,
        placeholder: String,
        addHelp: String,
        removeHelp: String,
        bundleIDs: [String],
        newBundleID: Binding<String>,
        add: @escaping (String) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(helper)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField(placeholder, text: newBundleID)
                    .textFieldStyle(.roundedBorder)

                Button {
                    add(newBundleID.wrappedValue)
                    newBundleID.wrappedValue = ""
                } label: {
                    Image(systemName: "plus")
                }
                .help(addHelp)
            }

            List {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            remove(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(removeHelp)
                    }
                }
            }
            .frame(minHeight: 110)
        }
    }
}
