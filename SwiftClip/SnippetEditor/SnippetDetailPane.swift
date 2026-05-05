import KeyboardShortcuts
import SwiftUI

struct SnippetDetailPane: View {
    @ObservedObject var snippets: SnippetStore
    var selection: SnippetSelection?

    var body: some View {
        switch selection {
        case .folder(let folderID):
            if let folder = snippets.folder(id: folderID) {
                folderView(folder)
            } else {
                emptyView
            }
        case .snippet(let folderID, let snippetID):
            if let snippet = snippets.snippet(folderID: folderID, snippetID: snippetID) {
                snippetView(folderID: folderID, snippet: snippet)
            } else {
                emptyView
            }
        case nil:
            emptyView
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            L10n.string("editor.empty.title"),
            systemImage: "sidebar.leading",
            description: Text(L10n.string("editor.empty.body"))
        )
    }

    private func folderView(_ folder: SnippetSummary) -> some View {
        Form {
            HStack(spacing: 14) {
                Image(systemName: "folder")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)

                TextField(
                    L10n.string("editor.folderName"),
                    text: Binding {
                        snippets.folder(id: folder.id)?.title ?? folder.title
                    } set: { newTitle in
                        snippets.updateFolder(id: folder.id, title: newTitle)
                    }
                )
                .font(.title2)
                .textFieldStyle(.roundedBorder)
            }

            Toggle(
                L10n.string("editor.enabled"),
                isOn: Binding {
                    snippets.folder(id: folder.id)?.isEnabled ?? folder.isEnabled
                } set: { isEnabled in
                    snippets.updateFolder(id: folder.id, isEnabled: isEnabled)
                }
            )

            KeyboardShortcuts.Recorder(L10n.string("editor.shortcut"), name: .folder(folder.id))

            Section(L10n.string("editor.snippetSharing")) {
                Text("Coming Soon")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func snippetView(folderID: UUID, snippet: SnippetLeaf) -> some View {
        Form {
            TextField(
                L10n.string("editor.snippetName"),
                text: Binding {
                    snippets.snippet(folderID: folderID, snippetID: snippet.id)?.title ?? snippet.title
                } set: { title in
                    snippets.updateSnippet(folderID: folderID, snippetID: snippet.id, title: title)
                }
            )
            .textFieldStyle(.roundedBorder)

            Toggle(
                L10n.string("editor.enabled"),
                isOn: Binding {
                    snippets.snippet(folderID: folderID, snippetID: snippet.id)?.isEnabled ?? snippet.isEnabled
                } set: { isEnabled in
                    snippets.updateSnippet(folderID: folderID, snippetID: snippet.id, isEnabled: isEnabled)
                }
            )

            KeyboardShortcuts.Recorder(L10n.string("editor.shortcut"), name: .snippet(snippet.id))

            TextEditor(
                text: Binding {
                    snippets.snippet(folderID: folderID, snippetID: snippet.id)?.content ?? snippet.content
                } set: { content in
                    snippets.updateSnippet(folderID: folderID, snippetID: snippet.id, content: content)
                }
            )
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 240)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
