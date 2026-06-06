import SwiftUI

private enum SnippetEditorLayout {
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 220
}

enum SnippetSelection: Hashable, Identifiable {
    case folder(UUID)
    case snippet(folderID: UUID, snippetID: UUID)

    var id: String {
        switch self {
        case .folder(let id):
            return "folder-\(id.uuidString)"
        case .snippet(let folderID, let snippetID):
            return "snippet-\(folderID.uuidString)-\(snippetID.uuidString)"
        }
    }
}

struct SnippetEditorWindow: View {
    private let environment: AppEnvironment
    @ObservedObject private var snippets: SnippetStore
    @State private var selection: SnippetSelection?
    @State private var expandedFolderIDs = Set<UUID>()

    init(environment: AppEnvironment) {
        self.environment = environment
        _snippets = ObservedObject(wrappedValue: environment.snippets)
    }

    var body: some View {
        HSplitView {
            SnippetOutlineView(
                snippets: snippets,
                selection: $selection,
                expandedFolderIDs: $expandedFolderIDs
            )
            .frame(
                minWidth: SnippetEditorLayout.sidebarMinWidth,
                idealWidth: SnippetEditorLayout.sidebarIdealWidth,
                maxWidth: SnippetEditorLayout.sidebarMaxWidth,
                maxHeight: .infinity
            )

            SnippetDetailPane(snippets: snippets, selection: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            SnippetToolbar(
                environment: environment,
                selection: $selection,
                expandedFolderIDs: $expandedFolderIDs
            )
        }
    }
}
