import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

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
                        snippetRow(folderID: folder.id, snippet: snippet)
                    }
                    .onMove { source, destination in
                        snippets.moveSnippets(in: folder.id, fromOffsets: source, toOffset: destination)
                    }
                } label: {
                    folderRow(folder)
                }
            }
            .onMove { source, destination in
                snippets.moveFolders(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.sidebar)
    }

    private func folderRow(_ folder: SnippetSummary) -> some View {
        outlineRow(
            title: folder.title,
            systemImage: folder.isEnabled ? "folder" : "folder.badge.minus",
            isEnabled: folder.isEnabled
        )
            .tag(SnippetSelection.folder(folder.id))
            .draggable(SnippetOutlineDragItem.folder(folder.id))
            .dropDestination(for: SnippetOutlineDragItem.self) { items, location in
                handleDrop(items, target: .folder(folder.id), location: location)
            }
    }

    private func snippetRow(folderID: UUID, snippet: SnippetLeaf) -> some View {
        outlineRow(
            title: snippet.title,
            systemImage: "text.alignleft",
            isEnabled: snippet.isEnabled
        )
            .tag(SnippetSelection.snippet(folderID: folderID, snippetID: snippet.id))
            .draggable(SnippetOutlineDragItem.snippet(folderID: folderID, snippetID: snippet.id))
            .dropDestination(for: SnippetOutlineDragItem.self) { items, location in
                handleDrop(items, target: .snippet(folderID: folderID, snippetID: snippet.id), location: location)
            }
    }

    private func outlineRow(title: String, systemImage: String, isEnabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .foregroundStyle(isEnabled ? .primary : .secondary)
    }

    @MainActor
    private func handleDrop(
        _ items: [SnippetOutlineDragItem],
        target: SnippetOutlineDropTarget,
        location: CGPoint
    ) -> Bool {
        guard let item = items.first else {
            return false
        }

        switch (item.kind, target) {
        case (.folder, .folder(let targetFolderID)):
            guard item.folderID != targetFolderID,
                  let destination = folderInsertionIndex(targetFolderID: targetFolderID, location: location) else {
                return false
            }

            snippets.moveFolder(id: item.folderID, toIndex: destination)
            selection = .folder(item.folderID)
            return true

        case (.snippet, .folder(let targetFolderID)):
            guard let snippetID = item.snippetID else {
                return false
            }

            snippets.moveSnippet(snippetID: snippetID, fromFolderID: item.folderID, toFolderID: targetFolderID)
            expandedFolderIDs.insert(targetFolderID)
            selection = .snippet(folderID: targetFolderID, snippetID: snippetID)
            return true

        case (.snippet, .snippet(let targetFolderID, let targetSnippetID)):
            guard let snippetID = item.snippetID,
                  snippetID != targetSnippetID,
                  let destination = snippetInsertionIndex(
                    targetFolderID: targetFolderID,
                    targetSnippetID: targetSnippetID,
                    location: location
                  ) else {
                return false
            }

            snippets.moveSnippet(
                snippetID: snippetID,
                fromFolderID: item.folderID,
                toFolderID: targetFolderID,
                toIndex: destination
            )
            expandedFolderIDs.insert(targetFolderID)
            selection = .snippet(folderID: targetFolderID, snippetID: snippetID)
            return true

        case (.folder, .snippet):
            return false
        }
    }

    private func folderInsertionIndex(targetFolderID: UUID, location: CGPoint) -> Int? {
        let folders = snippets.allFolders()
        guard let targetIndex = folders.firstIndex(where: { $0.id == targetFolderID }) else {
            return nil
        }

        return location.y < 12 ? targetIndex : targetIndex + 1
    }

    private func snippetInsertionIndex(targetFolderID: UUID, targetSnippetID: UUID, location: CGPoint) -> Int? {
        guard let targetFolder = snippets.folder(id: targetFolderID) else {
            return nil
        }

        let snippets = targetFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }
        guard let targetIndex = snippets.firstIndex(where: { $0.id == targetSnippetID }) else {
            return nil
        }

        return location.y < 12 ? targetIndex : targetIndex + 1
    }
}

private enum SnippetOutlineDropTarget {
    case folder(UUID)
    case snippet(folderID: UUID, snippetID: UUID)
}

private struct SnippetOutlineDragItem: Codable, Hashable, Transferable {
    enum Kind: String, Codable, Hashable {
        case folder
        case snippet
    }

    var kind: Kind
    var folderID: UUID
    var snippetID: UUID?

    static func folder(_ id: UUID) -> Self {
        Self(kind: .folder, folderID: id)
    }

    static func snippet(folderID: UUID, snippetID: UUID) -> Self {
        Self(kind: .snippet, folderID: folderID, snippetID: snippetID)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swiftClipSnippetOutlineItem)
    }
}

private extension UTType {
    static let swiftClipSnippetOutlineItem = UTType(exportedAs: "app.swiftclip.snippet-outline-item")
}
