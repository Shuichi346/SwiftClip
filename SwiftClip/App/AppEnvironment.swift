import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let preferences: PreferencesStore
    let snippets: SnippetStore
    let blobStore: BlobStore
    let history: HistoryStore
    let pasteEngine: PasteEngine

    var openPreferences: (() -> Void)?
    var openSnippetEditor: (() -> Void)?
    var openPermissions: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        do {
            try FileLocations.ensureBaseDirectories()
        } catch {
            AppLog.app.error("Could not create app support directories: \(error.localizedDescription, privacy: .public)")
        }

        preferences = PreferencesStore()
        snippets = SnippetStore()
        blobStore = BlobStore(directoryURL: FileLocations.blobDirectoryURL)
        history = HistoryStore(blobStore: blobStore, preferences: preferences)
        pasteEngine = PasteEngine(preferences: preferences, blobStore: blobStore)
    }

    func start() async {
        await preferences.load()
        async let snippetsLoad: Void = snippets.load()
        async let historyLoad: Void = history.load()
        _ = await (snippetsLoad, historyLoad)

        preferences.$state
            .map(\.historyLimit)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak history] limit in
                history?.applyLimit(limit)
            }
            .store(in: &cancellables)
    }

    func flushPersistence() async {
        await history.flushPersistence()
        snippets.flushPersistence()
        preferences.flushPersistence()
    }
}
