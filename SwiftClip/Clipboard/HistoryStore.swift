import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let blobStore: BlobStore
    private let preferences: PreferencesStore
    private let fileURL: URL

    init(
        blobStore: BlobStore,
        preferences: PreferencesStore,
        fileURL: URL = FileLocations.historyIndexURL
    ) {
        self.blobStore = blobStore
        self.preferences = preferences
        self.fileURL = fileURL
    }

    func load() {
        do {
            try FileLocations.ensureBaseDirectories()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                persistSnapshot([])
                return
            }

            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            Task {
                await blobStore.sweep(keeping: Set(items.compactMap(\.blobFilename)))
            }
        } catch {
            AppLog.history.error("Could not load history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func item(id: UUID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    func add(_ capture: ClipboardCapture) {
        guard capture.byteCount <= PreferencesState.maximumPayloadBytes else {
            AppLog.clipboard.debug("Skipped oversized clipboard item")
            return
        }

        Task {
            await insert(capture)
        }
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = items.remove(at: index)
        if let blobFilename = removed.blobFilename {
            Task {
                await blobStore.delete(filename: blobFilename)
            }
        }
        persistSnapshot(items)
    }

    func clearAll() {
        items.removeAll()
        persistSnapshot([])
        Task {
            await blobStore.clearAll()
        }
    }

    private func insert(_ capture: ClipboardCapture) async {
        var blobFilename: String?
        var pasteboardTypeIdentifier = capture.pasteboardTypeIdentifier

        if let data = capture.data {
            do {
                let reference = try await blobStore.write(
                    data: data,
                    fileExtension: capture.kind.defaultFileExtension,
                    pasteboardTypeIdentifier: capture.pasteboardTypeIdentifier ?? capture.kind.fallbackPasteboardType.rawValue
                )
                blobFilename = reference.filename
                pasteboardTypeIdentifier = reference.pasteboardTypeIdentifier
            } catch {
                AppLog.history.error("Could not write clipboard blob: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        let item = ClipboardItem(
            kind: capture.kind,
            title: capture.title,
            textValue: capture.textValue,
            fileURLs: capture.fileURLs,
            blobFilename: blobFilename,
            byteCount: capture.byteCount,
            pasteboardTypeIdentifier: pasteboardTypeIdentifier
        )

        items.removeAll { existing in
            existing.textValue == item.textValue &&
            existing.fileURLs == item.fileURLs &&
            existing.blobFilename == nil &&
            item.blobFilename == nil
        }
        items.insert(item, at: 0)

        let limit = preferences.state.historyLimit
        if items.count > limit {
            let evicted = Array(items.dropFirst(limit))
            items = Array(items.prefix(limit))
            for item in evicted {
                if let blobFilename = item.blobFilename {
                    await blobStore.delete(filename: blobFilename)
                }
            }
        }

        persistSnapshot(items)
    }

    private func persistSnapshot(_ snapshot: [ClipboardItem]) {
        let fileURL = fileURL

        Task.detached(priority: .utility) {
            do {
                try FileLocations.ensureBaseDirectories()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                AppLog.history.error("Could not persist history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
