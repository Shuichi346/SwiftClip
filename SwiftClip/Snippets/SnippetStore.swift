import Combine
import Foundation

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var folders: [SnippetSummary] = []

    private let fileURL: URL
    private let persistenceQueue = JSONPersistenceQueue(label: "app.swiftclip.snippets.persistence")
    private let attachmentStore: SnippetAttachmentStore
    private let backupStore: SnippetLibraryBackupStore
    private var isBulkOperationInProgress = false

    init(
        fileURL: URL = FileLocations.snippetsIndexURL,
        attachmentDirectoryURL: URL = FileLocations.snippetAttachmentDirectoryURL,
        backupDirectoryURL: URL? = nil
    ) {
        self.fileURL = fileURL
        attachmentStore = SnippetAttachmentStore(directoryURL: attachmentDirectoryURL)
        backupStore = SnippetLibraryBackupStore(
            backupDirectoryURL: backupDirectoryURL
                ?? fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true),
            attachmentDirectoryURL: attachmentDirectoryURL
        )
    }

    func load() async {
        do {
            guard let decoded = try await Self.readFolders(from: fileURL) else {
                persist()
                return
            }

            folders = normalized(orderedBySortIndex(decoded, keyPath: \.sortIndex), orderSnippetsBySortIndex: true)
        } catch {
            AppLog.snippets.error("Could not load snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    func allFolders() -> [SnippetSummary] {
        folders
    }

    func enabledFolders() -> [SnippetSummary] {
        allFolders().filter(\.isEnabled).map { folder in
            var copy = folder
            copy.snippets = folder.snippets
                .filter(\.isEnabled)
            return copy
        }
    }

    @discardableResult
    func addFolder(title: String = L10n.string("editor.untitledFolder")) -> UUID {
        guard !isBulkOperationInProgress else {
            return UUID()
        }

        let folderID = UUID()
        let sortIndex = folders.count
        folders.append(SnippetSummary(id: folderID, title: title, sortIndex: sortIndex))
        persist()
        return folderID
    }

    @discardableResult
    func addSnippet(
        to folderID: UUID?,
        title: String = L10n.string("editor.untitledSnippet"),
        content: String = "",
        attachmentURLs: [String] = []
    ) -> UUID? {
        guard !isBulkOperationInProgress else {
            return nil
        }

        let targetFolderID = folderID ?? folders.first?.id ?? addFolder()
        guard let folderIndex = folders.firstIndex(where: { $0.id == targetFolderID }) else {
            return nil
        }

        let snippetID = UUID()
        let sortIndex = folders[folderIndex].snippets.count
        folders[folderIndex].snippets.append(
            SnippetLeaf(
                id: snippetID,
                title: title,
                content: content,
                attachmentURLs: attachmentURLs,
                sortIndex: sortIndex
            )
        )
        persist()
        return snippetID
    }

    func updateFolder(id: UUID, title: String? = nil, isEnabled: Bool? = nil) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let title {
            folders[index].title = title
        }
        if let isEnabled {
            folders[index].isEnabled = isEnabled
        }
        persist(debounced: title != nil && isEnabled == nil)
    }

    func updateSnippet(
        folderID: UUID,
        snippetID: UUID,
        title: String? = nil,
        content: String? = nil,
        attachmentURLs: [String]? = nil,
        isEnabled: Bool? = nil
    ) {
        guard !isBulkOperationInProgress else {
            return
        }

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
        var removedAttachmentURLs: [String] = []
        if let attachmentURLs {
            removedAttachmentURLs = folders[folderIndex].snippets[snippetIndex].attachmentURLs
            folders[folderIndex].snippets[snippetIndex].attachmentURLs = normalizedAttachmentURLs(attachmentURLs)
        }
        if let isEnabled {
            folders[folderIndex].snippets[snippetIndex].isEnabled = isEnabled
        }
        let shouldDebounce = removedAttachmentURLs.isEmpty
            && isEnabled == nil
            && (title != nil || content != nil)
        persist(debounced: shouldDebounce, deleting: removedAttachmentURLs)
    }

    func addAttachmentURLs(_ attachmentURLs: [String], folderID: UUID, snippetID: UUID) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              let snippetIndex = folders[folderIndex].snippets.firstIndex(where: { $0.id == snippetID }) else {
            return
        }

        let existing = folders[folderIndex].snippets[snippetIndex].attachmentURLs
        folders[folderIndex].snippets[snippetIndex].attachmentURLs = normalizedAttachmentURLs(existing + attachmentURLs)
        persist()
    }

    @discardableResult
    func addAttachmentFiles(_ fileURLs: [URL], folderID: UUID, snippetID: UUID) async throws -> [String] {
        guard !isBulkOperationInProgress else {
            return []
        }

        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              folders[folderIndex].snippets.contains(where: { $0.id == snippetID }) else {
            return []
        }

        let copiedURLs = try await attachmentStore.copyFiles(fileURLs)
        guard !isBulkOperationInProgress,
              let currentFolderIndex = folders.firstIndex(where: { $0.id == folderID }),
              let snippetIndex = folders[currentFolderIndex].snippets.firstIndex(where: { $0.id == snippetID }) else {
            for copiedURL in copiedURLs {
                await attachmentStore.deleteIfManaged(copiedURL.absoluteString)
            }
            return []
        }

        let copiedAttachmentURLs = copiedURLs.map(\.absoluteString)
        let existing = folders[currentFolderIndex].snippets[snippetIndex].attachmentURLs
        folders[currentFolderIndex].snippets[snippetIndex].attachmentURLs = normalizedAttachmentURLs(
            existing + copiedAttachmentURLs
        )
        persist()
        return copiedAttachmentURLs
    }

    func removeAttachmentURL(at index: Int, folderID: UUID, snippetID: UUID) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              let snippetIndex = folders[folderIndex].snippets.firstIndex(where: { $0.id == snippetID }),
              folders[folderIndex].snippets[snippetIndex].attachmentURLs.indices.contains(index) else {
            return
        }

        let removedAttachmentURL = folders[folderIndex].snippets[snippetIndex].attachmentURLs[index]
        folders[folderIndex].snippets[snippetIndex].attachmentURLs.remove(at: index)
        persist(deleting: [removedAttachmentURL])
    }

    func deleteFolder(id: UUID) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let removedFolder = folders.first(where: { $0.id == id }) else {
            return
        }

        let removedAttachmentURLs = removedFolder.snippets.flatMap(\.attachmentURLs)
        folders.removeAll { $0.id == id }
        normalizeSortIndexes()
        persist(
            deleting: removedAttachmentURLs,
            removingShortcutsFrom: [removedFolder]
        )
    }

    func deleteSnippet(folderID: UUID, snippetID: UUID) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        guard let removedSnippet = folders[folderIndex].snippets.first(where: { $0.id == snippetID }) else {
            return
        }

        let removedAttachmentURLs = removedSnippet.attachmentURLs
        let shortcutCleanupFolder = SnippetSummary(
            id: folders[folderIndex].id,
            title: folders[folderIndex].title,
            sortIndex: folders[folderIndex].sortIndex,
            isEnabled: folders[folderIndex].isEnabled,
            snippets: [removedSnippet]
        )
        folders[folderIndex].snippets.removeAll { $0.id == snippetID }
        normalizeSnippetSortIndexes(folderIndex: folderIndex)
        persist(
            deleting: removedAttachmentURLs,
            removingShortcutsFrom: [shortcutCleanupFolder]
        )
    }

    func moveFolders(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isBulkOperationInProgress else {
            return
        }

        var orderedFolders = allFolders()
        orderedFolders.move(fromOffsets: source, toOffset: destination)
        folders = normalized(orderedFolders)
        persist()
    }

    func moveFolder(id: UUID, toIndex destination: Int) {
        guard !isBulkOperationInProgress else {
            return
        }

        var orderedFolders = allFolders()
        guard let sourceIndex = orderedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let folder = orderedFolders.remove(at: sourceIndex)
        let boundedDestination = min(max(0, destination), orderedFolders.count + 1)
        let adjustedDestination = sourceIndex < boundedDestination ? boundedDestination - 1 : boundedDestination
        orderedFolders.insert(folder, at: min(max(0, adjustedDestination), orderedFolders.count))
        folders = normalized(orderedFolders)
        persist()
    }

    func moveSnippets(in folderID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        var orderedSnippets = folders[folderIndex].snippets.sorted { $0.sortIndex < $1.sortIndex }
        orderedSnippets.move(fromOffsets: source, toOffset: destination)
        folders[folderIndex].snippets = normalizedSnippets(orderedSnippets)
        persist()
    }

    func moveSnippet(snippetID: UUID, fromFolderID: UUID, toFolderID: UUID, toIndex destination: Int? = nil) {
        guard !isBulkOperationInProgress else {
            return
        }

        guard let sourceFolderIndex = folders.firstIndex(where: { $0.id == fromFolderID }),
              let targetFolderIndex = folders.firstIndex(where: { $0.id == toFolderID }) else {
            return
        }

        if fromFolderID == toFolderID {
            moveSnippetWithinFolder(folderIndex: sourceFolderIndex, snippetID: snippetID, toIndex: destination)
            persist()
            return
        }

        var sourceSnippets = folders[sourceFolderIndex].snippets.sorted { $0.sortIndex < $1.sortIndex }
        guard let sourceSnippetIndex = sourceSnippets.firstIndex(where: { $0.id == snippetID }) else {
            return
        }

        let snippet = sourceSnippets.remove(at: sourceSnippetIndex)
        folders[sourceFolderIndex].snippets = normalizedSnippets(sourceSnippets)

        var targetSnippets = folders[targetFolderIndex].snippets.sorted { $0.sortIndex < $1.sortIndex }
        let insertionIndex = min(max(0, destination ?? targetSnippets.count), targetSnippets.count)
        targetSnippets.insert(snippet, at: insertionIndex)
        folders[targetFolderIndex].snippets = normalizedSnippets(targetSnippets)
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

    func replaceAll(with importedFolders: [SnippetSummary]) async throws {
        guard !isBulkOperationInProgress else {
            throw SwiftClipError.snippetsPersistenceFailed("Another snippet operation is already in progress.")
        }

        isBulkOperationInProgress = true
        defer {
            isBulkOperationInProgress = false
        }

        let previousFolders = folders
        let shortcuts = SnippetShortcutStorage.backupRecords(for: previousFolders)
        _ = try await backupStore.createBackup(folders: previousFolders, shortcuts: shortcuts)

        let replacement = normalized(importedFolders)
        try await persistenceQueue.writeAndWait(replacement, to: fileURL)

        SnippetShortcutStorage.removeShortcuts(
            removedFrom: previousFolders,
            retainedIn: replacement
        )
        folders = replacement
        await deleteUnreferencedManagedAttachments(
            previousFolders.flatMap { $0.snippets.flatMap(\.attachmentURLs) }
        )
    }

    func restoreBackup(from backupURL: URL) async throws {
        guard !isBulkOperationInProgress else {
            throw SwiftClipError.snippetsPersistenceFailed("Another snippet operation is already in progress.")
        }

        isBulkOperationInProgress = true
        defer {
            isBulkOperationInProgress = false
        }

        let previousFolders = folders
        let currentShortcuts = SnippetShortcutStorage.backupRecords(for: previousFolders)
        _ = try await backupStore.createBackup(
            folders: previousFolders,
            shortcuts: currentShortcuts
        )

        let preparedRestore = try await backupStore.prepareRestore(from: backupURL)
        let restoredFolders = normalized(preparedRestore.folders)
        do {
            try await persistenceQueue.writeAndWait(restoredFolders, to: fileURL)
        } catch {
            await backupStore.discardPreparedRestore(preparedRestore)
            throw error
        }

        SnippetShortcutStorage.restore(preparedRestore.shortcuts)
        folders = restoredFolders
        await deleteUnreferencedManagedAttachments(
            previousFolders.flatMap { $0.snippets.flatMap(\.attachmentURLs) }
        )
    }

    func append(_ importedFolders: [SnippetSummary]) {
        guard !isBulkOperationInProgress else {
            return
        }

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
                        attachmentURLs: snippet.attachmentURLs,
                        sortIndex: snippetOffset,
                        isEnabled: snippet.isEnabled
                    )
                }
            )
        }
        folders.append(contentsOf: appended)
        persist()
    }

    private func normalized(
        _ importedFolders: [SnippetSummary],
        orderSnippetsBySortIndex: Bool = false
    ) -> [SnippetSummary] {
        importedFolders.enumerated().map { folderOffset, folder in
            let snippets = orderSnippetsBySortIndex
                ? orderedBySortIndex(folder.snippets, keyPath: \.sortIndex)
                : folder.snippets

            return SnippetSummary(
                id: folder.id,
                title: folder.title,
                sortIndex: folderOffset,
                isEnabled: folder.isEnabled,
                snippets: snippets.enumerated().map { snippetOffset, snippet in
                    SnippetLeaf(
                        id: snippet.id,
                        title: snippet.title,
                        content: snippet.content,
                        attachmentURLs: snippet.attachmentURLs,
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
        folders[folderIndex].snippets = normalizedSnippets(folders[folderIndex].snippets)
    }

    private func moveSnippetWithinFolder(folderIndex: Int, snippetID: UUID, toIndex destination: Int?) {
        var orderedSnippets = folders[folderIndex].snippets.sorted { $0.sortIndex < $1.sortIndex }
        guard let sourceIndex = orderedSnippets.firstIndex(where: { $0.id == snippetID }) else {
            return
        }

        let snippet = orderedSnippets.remove(at: sourceIndex)
        if let destination {
            let boundedDestination = min(max(0, destination), orderedSnippets.count + 1)
            let adjustedDestination = sourceIndex < boundedDestination ? boundedDestination - 1 : boundedDestination
            orderedSnippets.insert(snippet, at: min(max(0, adjustedDestination), orderedSnippets.count))
        } else {
            orderedSnippets.append(snippet)
        }
        folders[folderIndex].snippets = normalizedSnippets(orderedSnippets)
    }

    private func normalizedSnippets(_ snippets: [SnippetLeaf]) -> [SnippetLeaf] {
        snippets.enumerated().map { offset, snippet in
            var copy = snippet
            copy.sortIndex = offset
            return copy
        }
    }

    private func normalizedAttachmentURLs(_ attachmentURLs: [String]) -> [String] {
        var seen: Set<String> = []
        return attachmentURLs.filter { attachmentURL in
            guard URL(string: attachmentURL)?.isFileURL == true else {
                return false
            }
            return seen.insert(attachmentURL).inserted
        }
    }

    private func orderedBySortIndex<Value>(
        _ values: [Value],
        keyPath: KeyPath<Value, Int>
    ) -> [Value] {
        values.enumerated()
            .sorted { first, second in
                let firstSortIndex = first.element[keyPath: keyPath]
                let secondSortIndex = second.element[keyPath: keyPath]
                if firstSortIndex == secondSortIndex {
                    return first.offset < second.offset
                }
                return firstSortIndex < secondSortIndex
            }
            .map(\.element)
    }

    private func deleteUnreferencedManagedAttachments(_ attachmentURLs: [String]) async {
        let referencedAttachmentURLs = Set(folders.flatMap { folder in
            folder.snippets.flatMap(\.attachmentURLs)
        })

        for attachmentURL in attachmentURLs where !referencedAttachmentURLs.contains(attachmentURL) {
            await attachmentStore.deleteIfManaged(attachmentURL)
        }
    }

    func flushPersistence() {
        persistenceQueue.flush()
    }

    private func persist(
        debounced: Bool = false,
        deleting removedAttachmentURLs: [String] = [],
        removingShortcutsFrom removedFolders: [SnippetSummary] = []
    ) {
        if !removedAttachmentURLs.isEmpty || !removedFolders.isEmpty {
            persistenceQueue.write(folders, to: fileURL) { [weak self] result in
                switch result {
                case .success:
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        SnippetShortcutStorage.removeShortcuts(
                            removedFrom: removedFolders,
                            retainedIn: folders
                        )
                        await deleteUnreferencedManagedAttachments(removedAttachmentURLs)
                    }
                case .failure(let error):
                    AppLog.snippets.error("Could not persist snippets: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        if debounced {
            persistenceQueue.writeDebounced(folders, to: fileURL) { error in
                AppLog.snippets.error("Could not persist snippets: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            persistenceQueue.write(folders, to: fileURL) { error in
                AppLog.snippets.error("Could not persist snippets: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func readFolders(from fileURL: URL) async throws -> [SnippetSummary]? {
        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([SnippetSummary].self, from: data)
        }.value
    }
}
