import SwiftUI

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
        NavigationSplitView {
            SnippetOutlineView(
                snippets: snippets,
                selection: $selection,
                expandedFolderIDs: $expandedFolderIDs
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            SnippetDetailPane(snippets: snippets, selection: selection)
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
