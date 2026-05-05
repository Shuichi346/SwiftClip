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

    func start() {
        preferences.load()
        snippets.load()
        history.load()
    }
}
