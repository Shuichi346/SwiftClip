import Combine
import Foundation

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var folders: [SnippetSummary] = []

    private let fileURL: URL

    init(fileURL: URL = FileLocations.snippetsIndexURL) {
        self.fileURL = fileURL
    }

    func load() {
        do {
            try FileLocations.ensureBaseDirectories()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                persist()
                return
            }

            let data = try Data(contentsOf: fileURL)
            folders = try JSONDecoder().decode([SnippetSummary].self, from: data).sorted { $0.sortIndex < $1.sortIndex }
        } catch {
            AppLog.snippets.error("Could not load snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    func allFolders() -> [SnippetSummary] {
        folders.sorted { $0.sortIndex < $1.sortIndex }
    }

    func enabledFolders() -> [SnippetSummary] {
        allFolders().filter(\.isEnabled).map { folder in
            var copy = folder
            copy.snippets = folder.snippets
                .filter(\.isEnabled)
                .sorted { $0.sortIndex < $1.sortIndex }
            return copy
        }
    }

    @discardableResult
    func addFolder(title: String = L10n.string("editor.untitledFolder")) -> UUID {
        let folderID = UUID()
        let sortIndex = folders.count
        folders.append(SnippetSummary(id: folderID, title: title, sortIndex: sortIndex))
        persist()
        return folderID
    }

    @discardableResult
    func addSnippet(to folderID: UUID?, title: String = L10n.string("editor.untitledSnippet"), content: String = "") -> UUID? {
        let targetFolderID = folderID ?? folders.first?.id ?? addFolder()
        guard let folderIndex = folders.firstIndex(where: { $0.id == targetFolderID }) else {
            return nil
        }

        let snippetID = UUID()
        let sortIndex = folders[folderIndex].snippets.count
        folders[folderIndex].snippets.append(
            SnippetLeaf(id: snippetID, title: title, content: content, sortIndex: sortIndex)
        )
        persist()
        return snippetID
    }

    func updateFolder(id: UUID, title: String? = nil, isEnabled: Bool? = nil) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let title {
            folders[index].title = title
        }
        if let isEnabled {
            folders[index].isEnabled = isEnabled
        }
        persist()
    }

    func updateSnippet(folderID: UUID, snippetID: UUID, title: String? = nil, content: String? = nil, isEnabled: Bool? = nil) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              let snippetIndex = folders[folderIndex].snippets.firstIndex(where: { $0.id == snippetID }) else {
            return
        }

        if let title {
            folders[folderIndex].snippets[snippetIndex].title = title
        }
        if let content {
            folders[folderIndex].snippets[snippetIndex].content = content
        }
        if let isEnabled {
            folders[folderIndex].snippets[snippetIndex].isEnabled = isEnabled
        }
        persist()
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        normalizeSortIndexes()
        persist()
    }

    func deleteSnippet(folderID: UUID, snippetID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        folders[folderIndex].snippets.removeAll { $0.id == snippetID }
        normalizeSnippetSortIndexes(folderIndex: folderIndex)
        persist()
    }

    func folder(id: UUID) -> SnippetSummary? {
        folders.first { $0.id == id }
    }

    func snippet(folderID: UUID, snippetID: UUID) -> SnippetLeaf? {
        folders
            .first { $0.id == folderID }?
            .snippets
            .first { $0.id == snippetID }
    }

    func replaceAll(with importedFolders: [SnippetSummary]) throws {
        try writeBackup()
        folders = normalized(importedFolders)
        persist()
    }

    func append(_ importedFolders: [SnippetSummary]) {
        let startIndex = folders.count
        let appended = importedFolders.enumerated().map { offset, folder in
            SnippetSummary(
                id: UUID(),
                title: folder.title,
                sortIndex: startIndex + offset,
                isEnabled: folder.isEnabled,
                snippets: folder.snippets.enumerated().map { snippetOffset, snippet in
                    SnippetLeaf(
                        id: UUID(),
                        title: snippet.title,
                        content: snippet.content,
                        sortIndex: snippetOffset,
                        isEnabled: snippet.isEnabled
                    )
                }
            )
        }
        folders.append(contentsOf: appended)
        persist()
    }

    private func writeBackup() throws {
        try FileLocations.ensureBaseDirectories()
        let data = try ClipyXMLCodec.encode(folders: allFolders())
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = FileLocations.backupDirectoryURL
            .appendingPathComponent("snippets-pre-import-\(stamp).xml", isDirectory: false)
        try data.write(to: backupURL, options: .atomic)
    }

    private func normalized(_ importedFolders: [SnippetSummary]) -> [SnippetSummary] {
        importedFolders.enumerated().map { folderOffset, folder in
            SnippetSummary(
                id: folder.id,
                title: folder.title,
                sortIndex: folderOffset,
                isEnabled: folder.isEnabled,
                snippets: folder.snippets.enumerated().map { snippetOffset, snippet in
                    SnippetLeaf(
                        id: snippet.id,
                        title: snippet.title,
                        content: snippet.content,
                        sortIndex: snippetOffset,
                        isEnabled: snippet.isEnabled
                    )
                }
            )
        }
    }

    private func normalizeSortIndexes() {
        folders = folders.enumerated().map { offset, folder in
            var copy = folder
            copy.sortIndex = offset
            return copy
        }
    }

    private func normalizeSnippetSortIndexes(folderIndex: Int) {
        folders[folderIndex].snippets = folders[folderIndex].snippets.enumerated().map { offset, snippet in
            var copy = snippet
            copy.sortIndex = offset
            return copy
        }
    }

    private func persist() {
        let folders = folders
        let fileURL = fileURL

        Task.detached(priority: .utility) {
            do {
                try FileLocations.ensureBaseDirectories()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(folders)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                AppLog.snippets.error("Could not persist snippets: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
