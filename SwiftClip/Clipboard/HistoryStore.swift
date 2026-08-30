import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let blobStore: any BlobStoring
    private let preferences: PreferencesStore
    private let fileURL: URL
    private let persistenceQueue = JSONPersistenceQueue(label: "app.swiftclip.history.persistence")
    private var captureGeneration: UInt64 = 0
    private var captureTasks: [UUID: Task<Void, Never>] = [:]

    init(
        blobStore: any BlobStoring,
        preferences: PreferencesStore,
        fileURL: URL = FileLocations.historyIndexURL
    ) {
        self.blobStore = blobStore
        self.preferences = preferences
        self.fileURL = fileURL
    }

    func load() async {
        do {
            let decoded = try await Self.readSnapshot(from: fileURL)
            guard var decoded else {
                items = []
                try await persistenceQueue.writeAndWait(
                    [ClipboardItem](),
                    to: fileURL,
                    encodeDatesAsISO8601: true
                )
                await blobStore.sweep(keeping: [])
                return
            }

            var didMigrate = false
            for index in decoded.indices {
                if let blobFilename = decoded[index].blobFilename,
                   (decoded[index].kind == .richText || decoded[index].kind == .rtfd),
                   let data = try? await blobStore.read(filename: blobFilename),
                   let richTextPreview = ClipboardCapture.richTextPreview(
                    data: data,
                    kind: decoded[index].kind
                   ),
                   richTextPreview != decoded[index].title {
                    decoded[index].title = richTextPreview
                    didMigrate = true
                }

                let preview = decoded[index].title.swiftClipTruncated(to: ClipboardCapture.titlePreviewLimit)
                if preview != decoded[index].title {
                    decoded[index].title = preview
                    didMigrate = true
                }

                guard decoded[index].blobFilename == nil,
                      decoded[index].kind == .plainText || decoded[index].kind == .url,
                      let textValue = decoded[index].textValue else {
                    continue
                }

                let data = Data(textValue.utf8)
                guard data.count > ClipboardCapture.inlineTextByteLimit else {
                    continue
                }

                do {
                    let reference = try await blobStore.write(
                        data: data,
                        fileExtension: decoded[index].kind.defaultFileExtension,
                        pasteboardTypeIdentifier: decoded[index].pasteboardTypeIdentifier
                            ?? decoded[index].kind.fallbackPasteboardType.rawValue
                    )
                    decoded[index].blobFilename = reference.filename
                    decoded[index].pasteboardTypeIdentifier = reference.pasteboardTypeIdentifier
                    decoded[index].textValue = nil
                    didMigrate = true
                } catch {
                    AppLog.history.error("Could not migrate inline history payload: \(error.localizedDescription, privacy: .public)")
                }
            }

            let limit = preferences.state.historyLimit
            let retained = Array(decoded.prefix(limit))
            let evictedFilenames = Set(decoded.dropFirst(limit).compactMap(\.blobFilename))
            if retained.count != decoded.count {
                didMigrate = true
            }

            items = retained
            if didMigrate {
                try await persistenceQueue.writeAndWait(items, to: fileURL, encodeDatesAsISO8601: true)
                await deleteBlobs(evictedFilenames)
            }

            await blobStore.sweep(keeping: Set(items.compactMap(\.blobFilename)))
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

        let taskID = UUID()
        let generation = captureGeneration
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            await insert(capture, generation: generation)
            captureTasks[taskID] = nil
        }
        captureTasks[taskID] = task
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = items.remove(at: index)
        persistSnapshot(items, deleting: Set([removed.blobFilename].compactMap { $0 }))
    }

    func clearAll() {
        captureGeneration &+= 1
        captureTasks.values.forEach { $0.cancel() }

        let removedFilenames = Set(items.compactMap(\.blobFilename))
        items.removeAll()
        persistSnapshot([], deleting: removedFilenames)
    }

    func applyLimit(_ limit: Int) {
        let boundedLimit = min(max(1, limit), PreferencesState.maximumHistoryLimit)
        guard items.count > boundedLimit else {
            return
        }

        let evictedFilenames = Set(items.dropFirst(boundedLimit).compactMap(\.blobFilename))
        items = Array(items.prefix(boundedLimit))
        persistSnapshot(items, deleting: evictedFilenames)
    }

    func flushPersistence() async {
        while !captureTasks.isEmpty {
            let tasks = Array(captureTasks.values)
            for task in tasks {
                await task.value
            }
        }
        persistenceQueue.flush()
    }

    private func insert(_ capture: ClipboardCapture, generation: UInt64) async {
        var blobFilename: String?
        var pasteboardTypeIdentifier = capture.pasteboardTypeIdentifier

        if let data = capture.data {
            do {
                let reference = try await blobStore.write(
                    data: data,
                    fileExtension: capture.kind.defaultFileExtension,
                    pasteboardTypeIdentifier: capture.pasteboardTypeIdentifier
                        ?? capture.kind.fallbackPasteboardType.rawValue
                )
                blobFilename = reference.filename
                pasteboardTypeIdentifier = reference.pasteboardTypeIdentifier
            } catch {
                AppLog.history.error("Could not write clipboard blob: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        guard !Task.isCancelled, generation == captureGeneration else {
            if let blobFilename {
                await blobStore.delete(filename: blobFilename)
            }
            return
        }

        let item = ClipboardItem(
            kind: capture.kind,
            title: capture.title.swiftClipTruncated(to: ClipboardCapture.titlePreviewLimit),
            textValue: capture.textValue,
            fileURLs: capture.fileURLs,
            blobFilename: blobFilename,
            byteCount: capture.byteCount,
            pasteboardTypeIdentifier: pasteboardTypeIdentifier
        )

        items.removeAll { existing in
            existing.textValue == item.textValue
                && existing.fileURLs == item.fileURLs
                && existing.blobFilename == nil
                && item.blobFilename == nil
        }
        items.insert(item, at: 0)

        let limit = preferences.state.historyLimit
        let evicted = items.count > limit ? Array(items.dropFirst(limit)) : []
        if !evicted.isEmpty {
            items = Array(items.prefix(limit))
        }

        persistSnapshot(items, deleting: Set(evicted.compactMap(\.blobFilename)))
    }

    private func persistSnapshot(_ snapshot: [ClipboardItem], deleting filenames: Set<String> = []) {
        let blobStore = blobStore
        persistenceQueue.write(
            snapshot,
            to: fileURL,
            encodeDatesAsISO8601: true
        ) { result in
            switch result {
            case .success:
                guard !filenames.isEmpty else {
                    return
                }
                Task {
                    for filename in filenames {
                        await blobStore.delete(filename: filename)
                    }
                }
            case .failure(let error):
                AppLog.history.error("Could not persist history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deleteBlobs(_ filenames: Set<String>) async {
        for filename in filenames {
            await blobStore.delete(filename: filename)
        }
    }

    private nonisolated static func readSnapshot(from fileURL: URL) async throws -> [ClipboardItem]? {
        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ClipboardItem].self, from: data)
        }.value
    }
}
