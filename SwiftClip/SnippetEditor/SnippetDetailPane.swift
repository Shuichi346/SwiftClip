import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct SnippetDetailPane: View {
    @ObservedObject var snippets: SnippetStore
    var selection: SnippetSelection?
    @State private var isAddingAttachments = false
    @State private var isFileDropTarget = false

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

            Section(L10n.string("editor.snippetContent")) {
                TextEditor(
                    text: Binding {
                        snippets.snippet(folderID: folderID, snippetID: snippet.id)?.content ?? snippet.content
                    } set: { content in
                        snippets.updateSnippet(folderID: folderID, snippetID: snippet.id, content: content)
                    }
                )
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay {
                    if isFileDropTarget {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTarget) { providers in
                    addDroppedAttachments(providers, folderID: folderID, snippetID: snippet.id)
                    return true
                }
            }

            attachmentsSection(folderID: folderID, snippet: snippet)
        }
        .formStyle(.grouped)
        .padding(20)
        .fileImporter(
            isPresented: $isAddingAttachments,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }

            snippets.addAttachmentURLs(urls.map(\.absoluteString), folderID: folderID, snippetID: snippet.id)
        }
    }

    private func attachmentsSection(folderID: UUID, snippet: SnippetLeaf) -> some View {
        Section {
            if snippet.attachmentURLs.isEmpty {
                Text(L10n.string("editor.attachments.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snippet.attachmentURLs.enumerated()), id: \.offset) { index, attachmentURL in
                    attachmentRow(attachmentURL: attachmentURL) {
                        snippets.removeAttachmentURL(at: index, folderID: folderID, snippetID: snippet.id)
                    }
                }
            }
        } header: {
            HStack {
                Text(L10n.string("editor.attachments"))
                Spacer()
                Button {
                    isAddingAttachments = true
                } label: {
                    Image(systemName: "paperclip.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("editor.attachments.add"))
            }
        }
    }

    private func attachmentRow(attachmentURL: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(for: attachmentURL))
                    .lineLimit(1)
                Text(filePath(for: attachmentURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("editor.attachments.remove"))
        }
    }

    private func addDroppedAttachments(_ providers: [NSItemProvider], folderID: UUID, snippetID: UUID) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let attachmentURL = Self.fileURLString(from: data) else {
                    return
                }

                Task { @MainActor in
                    snippets.addAttachmentURLs([attachmentURL], folderID: folderID, snippetID: snippetID)
                }
            }
        }
    }

    nonisolated private static func fileURLString(from data: Data) -> String? {
        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url.absoluteString
        }

        guard let string = String(data: data, encoding: .utf8),
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.isFileURL else {
            return nil
        }
        return url.absoluteString
    }

    private func fileName(for attachmentURL: String) -> String {
        URL(string: attachmentURL)?.lastPathComponent.nonEmpty ?? attachmentURL
    }

    private func filePath(for attachmentURL: String) -> String {
        URL(string: attachmentURL)?.path(percentEncoded: false) ?? attachmentURL
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
