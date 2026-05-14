import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExcludedAppsTab: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            bundleIDSection(
                title: L10n.string("prefs.excluded.title"),
                helper: L10n.string("prefs.excluded.helper"),
                addTitle: L10n.string("prefs.apps.choose"),
                addHelp: L10n.string("prefs.excluded.choose"),
                removeHelp: L10n.string("prefs.excluded.remove"),
                bundleIDs: preferences.state.excludedBundleIDs,
                addBundleIDs: { bundleIDs in
                    bundleIDs.forEach(preferences.addExcludedBundleID)
                },
                remove: preferences.removeExcludedBundleID
            )

            Divider()

            bundleIDSection(
                title: L10n.string("prefs.mixedPaste.title"),
                helper: L10n.string("prefs.mixedPaste.helper"),
                addTitle: L10n.string("prefs.apps.choose"),
                addHelp: L10n.string("prefs.mixedPaste.choose"),
                removeHelp: L10n.string("prefs.mixedPaste.remove"),
                bundleIDs: preferences.state.mixedSnippetPasteBundleIDs,
                addBundleIDs: { bundleIDs in
                    bundleIDs.forEach(preferences.addMixedSnippetPasteBundleID)
                },
                remove: preferences.removeMixedSnippetPasteBundleID
            )
        }
        .padding(20)
    }

    private func bundleIDSection(
        title: String,
        helper: String,
        addTitle: String,
        addHelp: String,
        removeHelp: String,
        bundleIDs: [String],
        addBundleIDs: @escaping ([String]) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(helper)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    let bundleIDs = chooseApplicationBundleIDs()
                    addBundleIDs(bundleIDs)
                } label: {
                    Label(addTitle, systemImage: "plus")
                }
                .help(addHelp)

                Spacer()
            }

            List {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(displayName(for: bundleID))
                            .lineLimit(1)
                            .help(bundleID)
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

    private func chooseApplicationBundleIDs() -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = L10n.string("prefs.apps.panelMessage")
        panel.prompt = L10n.string("prefs.apps.panelPrompt")
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else {
            return []
        }

        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }

        return url.lastPathComponent
    }
}
