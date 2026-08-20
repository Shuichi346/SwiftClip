import Combine
import Foundation
import KeyboardShortcuts

@MainActor
final class ShortcutCoordinator {
    struct Plan: Equatable {
        struct Folder: Equatable {
            var id: UUID
            var isEnabled: Bool
            var snippets: [Snippet]
        }

        struct Snippet: Equatable {
            var id: UUID
            var isEnabled: Bool
        }

        var folders: [Folder]

        init(folders: [SnippetSummary]) {
            self.folders = folders.map { folder in
                Folder(
                    id: folder.id,
                    isEnabled: folder.isEnabled,
                    snippets: folder.snippets.map {
                        Snippet(id: $0.id, isEnabled: folder.isEnabled && $0.isEnabled)
                    }
                )
            }
        }
    }

    private enum DynamicTarget: Hashable {
        case folder(UUID)
        case snippet(UUID)

        var name: KeyboardShortcuts.Name {
            switch self {
            case .folder(let id):
                return .folder(id)
            case .snippet(let id):
                return .snippet(id)
            }
        }
    }

    private let environment: AppEnvironment
    private weak var statusItemController: StatusItemController?
    private var fixedTasks: [KeyboardShortcuts.Name: Task<Void, Never>] = [:]
    private var dynamicTasks: [DynamicTarget: Task<Void, Never>] = [:]
    private var foldersCancellable: AnyCancellable?

    init(environment: AppEnvironment, statusItemController: StatusItemController) {
        self.environment = environment
        self.statusItemController = statusItemController
    }

    func start() {
        stop()
        SnippetShortcutStorage.migrateAndPrune(folders: environment.snippets.allFolders())
        registerFixedShortcuts()
        reconcile(Plan(folders: environment.snippets.allFolders()))

        foldersCancellable = environment.snippets.$folders
            .map(Plan.init(folders:))
            .removeDuplicates()
            .sink { [weak self] plan in
                self?.reconcile(plan)
            }
    }

    func stop() {
        fixedTasks.values.forEach { $0.cancel() }
        dynamicTasks.values.forEach { $0.cancel() }
        fixedTasks.removeAll()
        dynamicTasks.removeAll()
        foldersCancellable?.cancel()
        foldersCancellable = nil
    }

    private func registerFixedShortcuts() {
        listen(to: .mainMenu) { [weak self] in
            self?.statusItemController?.showStandalonePopupAtCursor()
        }
        listen(to: .clearHistory) { [weak self] in
            self?.environment.history.clearAll()
        }
        listen(to: .snippetEditor) { [weak self] in
            self?.environment.openSnippetEditor?()
        }
        listen(to: .preferences) { [weak self] in
            self?.environment.openPreferences?()
        }
        listen(to: .plainTextPaste) { [weak self] in
            guard let self,
                  let item = environment.history.items.first else {
                return
            }
            environment.pasteEngine.paste(item: item, asPlainText: true)
        }
    }

    private func listen(
        to name: KeyboardShortcuts.Name,
        action: @escaping @MainActor () -> Void
    ) {
        fixedTasks[name] = Task {
            for await _ in KeyboardShortcuts.events(.keyUp, for: name) {
                action()
            }
        }
    }

    private func reconcile(_ plan: Plan) {
        var enabledTargets: Set<DynamicTarget> = []
        for folder in plan.folders {
            if folder.isEnabled {
                enabledTargets.insert(.folder(folder.id))
            }
            for snippet in folder.snippets where snippet.isEnabled {
                enabledTargets.insert(.snippet(snippet.id))
            }
        }

        let removedTargets = dynamicTasks.keys.filter { !enabledTargets.contains($0) }
        for target in removedTargets {
            dynamicTasks[target]?.cancel()
            dynamicTasks[target] = nil
        }

        for target in enabledTargets where dynamicTasks[target] == nil {
            let name = target.name
            dynamicTasks[target] = Task { [weak self] in
                for await _ in KeyboardShortcuts.events(.keyUp, for: name) {
                    self?.dispatch(target)
                }
            }
        }

        removeDuplicateAssignments(plan: plan)
    }

    private func dispatch(_ target: DynamicTarget) {
        switch target {
        case .folder(let folderID):
            guard let folder = environment.snippets.folder(id: folderID),
                  folder.isEnabled else {
                return
            }
            statusItemController?.showSnippetFolderPopupAtCursor(folderID: folderID)

        case .snippet(let snippetID):
            guard let folder = environment.snippets.allFolders().first(where: {
                $0.isEnabled && $0.snippets.contains(where: { $0.id == snippetID && $0.isEnabled })
            }),
            let snippet = folder.snippets.first(where: { $0.id == snippetID && $0.isEnabled }) else {
                return
            }
            environment.pasteEngine.paste(snippet: snippet)
        }
    }

    private func removeDuplicateAssignments(plan: Plan) {
        let fixedNames: [KeyboardShortcuts.Name] = [
            .mainMenu,
            .clearHistory,
            .snippetEditor,
            .preferences,
            .plainTextPaste,
        ]
        let dynamicNames = plan.folders.flatMap { folder -> [KeyboardShortcuts.Name] in
            [.folder(folder.id)] + folder.snippets.map { .snippet($0.id) }
        }
        let names = fixedNames + dynamicNames.sorted { $0.rawValue < $1.rawValue }

        var ownerByShortcut: [KeyboardShortcuts.Shortcut: KeyboardShortcuts.Name] = [:]
        for name in names {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
                continue
            }
            if let owner = ownerByShortcut[shortcut] {
                KeyboardShortcuts.setShortcut(nil, for: name)
                AppLog.app.error(
                    "Removed duplicate shortcut \(name.rawValue, privacy: .public); already used by \(owner.rawValue, privacy: .public)"
                )
            } else {
                ownerByShortcut[shortcut] = name
            }
        }
    }
}
