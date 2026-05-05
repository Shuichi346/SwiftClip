import SwiftUI

struct SnippetOutlineView: View {
    @ObservedObject var snippets: SnippetStore
    @Binding var selection: SnippetSelection?
    @Binding var expandedFolderIDs: Set<UUID>

    var body: some View {
        List(selection: $selection) {
            ForEach(snippets.allFolders()) { folder in
                DisclosureGroup(
                    isExpanded: Binding {
                        expandedFolderIDs.contains(folder.id)
                    } set: { isExpanded in
                        if isExpanded {
                            expandedFolderIDs.insert(folder.id)
                        } else {
                            expandedFolderIDs.remove(folder.id)
                        }
                    }
                ) {
                    ForEach(folder.snippets.sorted { $0.sortIndex < $1.sortIndex }) { snippet in
                        Label(snippet.title, systemImage: snippet.isEnabled ? "text.alignleft" : "text.alignleft")
                            .foregroundStyle(snippet.isEnabled ? .primary : .secondary)
                            .tag(SnippetSelection.snippet(folderID: folder.id, snippetID: snippet.id))
                    }
                } label: {
                    Label(folder.title, systemImage: folder.isEnabled ? "folder" : "folder.badge.minus")
                        .foregroundStyle(folder.isEnabled ? .primary : .secondary)
                        .tag(SnippetSelection.folder(folder.id))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
