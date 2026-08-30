import AppKit
import XCTest
@testable import SwiftClip

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testLoadDecodesPersistedISO8601Dates() async throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("History.json", isDirectory: false)
        let preferences = PreferencesStore(fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false))
        let item = ClipboardItem(
            id: UUID(uuidString: "7EF784BB-6224-446C-A4C3-62FD73C2F4DB")!,
            kind: .plainText,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Persisted text",
            textValue: "Persisted text",
            byteCount: 14
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([item])
        try data.write(to: historyURL, options: .atomic)

        let store = HistoryStore(
            blobStore: BlobStore(directoryURL: root.appendingPathComponent("Blobs", isDirectory: true)),
            preferences: preferences,
            fileURL: historyURL
        )
        await store.load()

        XCTAssertEqual(store.items, [item])
    }

    func testLoadReplacesGenericRichTextTitleWithBlobPreview() async throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("History.json", isDirectory: false)
        let blobStore = BlobStore(directoryURL: root.appendingPathComponent("Blobs", isDirectory: true))
        let attributedString = NSAttributedString(string: "Persisted styled text")
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let reference = try await blobStore.write(
            data: rtfData,
            fileExtension: "rtf",
            pasteboardTypeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue
        )
        let item = ClipboardItem(
            kind: .richText,
            title: L10n.string("history.richText"),
            blobFilename: reference.filename,
            byteCount: rtfData.count,
            pasteboardTypeIdentifier: reference.pasteboardTypeIdentifier
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(to: historyURL, options: .atomic)
        let store = HistoryStore(
            blobStore: blobStore,
            preferences: PreferencesStore(
                fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false)
            ),
            fileURL: historyURL
        )

        await store.load()

        XCTAssertEqual(store.items.first?.title, "Persisted styled text")
        let persistedData = try Data(contentsOf: historyURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode([ClipboardItem].self, from: persistedData).first?.title,
            "Persisted styled text"
        )
    }

    func testHistoryLimitEvictsOldBlobs() async throws {
        let root = try temporaryDirectory()
        let blobDirectory = root.appendingPathComponent("Blobs", isDirectory: true)
        let historyURL = root.appendingPathComponent("History.json", isDirectory: false)
        let preferences = PreferencesStore(fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false))
        preferences.update { state in
            state.historyLimit = 3
        }

        let store = HistoryStore(
            blobStore: BlobStore(directoryURL: blobDirectory),
            preferences: preferences,
            fileURL: historyURL
        )

        for index in 0..<5 {
            store.add(
                ClipboardCapture(
                    kind: .richText,
                    title: "Item \(index)",
                    textValue: nil,
                    fileURLs: [],
                    data: Data("Item \(index)".utf8),
                    byteCount: 6,
                    pasteboardTypeIdentifier: "public.rtf"
                )
            )
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.items.count, 3)
        let blobCount = try FileManager.default.contentsOfDirectory(atPath: blobDirectory.path).count
        XCTAssertEqual(blobCount, 3)
    }

    func testClearAllCancelsInFlightBlobCapture() async throws {
        let root = try temporaryDirectory()
        let blobs = SuspendedBlobStore()
        let store = HistoryStore(
            blobStore: blobs,
            preferences: PreferencesStore(
                fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false)
            ),
            fileURL: root.appendingPathComponent("History.json", isDirectory: false)
        )

        store.add(
            ClipboardCapture(
                kind: .richText,
                title: "Delayed",
                textValue: nil,
                fileURLs: [],
                data: Data("delayed".utf8),
                byteCount: 7,
                pasteboardTypeIdentifier: "public.rtf"
            )
        )
        await blobs.waitUntilWriteStarts()

        store.clearAll()
        await blobs.resumeWrite()
        await store.flushPersistence()

        XCTAssertTrue(store.items.isEmpty)
        let deletedFilenames = await blobs.deletedFilenames()
        XCTAssertEqual(deletedFilenames, [SuspendedBlobStore.filename])

        let data = try Data(contentsOf: root.appendingPathComponent("History.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([ClipboardItem].self, from: data), [])
    }

    func testApplyLimitEvictsImmediatelyAndPersistsTheResult() async throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("History.json", isDirectory: false)
        let preferences = PreferencesStore(
            fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false)
        )
        preferences.update { $0.historyLimit = 10 }
        let store = HistoryStore(
            blobStore: BlobStore(directoryURL: root.appendingPathComponent("Blobs", isDirectory: true)),
            preferences: preferences,
            fileURL: historyURL
        )

        for index in 0..<5 {
            let text = "Item \(index)"
            store.add(
                ClipboardCapture(
                    kind: .plainText,
                    title: text,
                    textValue: text,
                    fileURLs: [],
                    data: nil,
                    byteCount: text.utf8.count,
                    pasteboardTypeIdentifier: "public.utf8-plain-text"
                )
            )
        }
        await store.flushPersistence()

        store.applyLimit(2)
        await store.flushPersistence()

        XCTAssertEqual(store.items.count, 2)
        let data = try Data(contentsOf: historyURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([ClipboardItem].self, from: data).count, 2)
    }

    func testLargeTextHistoryKeepsTheJSONIndexBounded() async throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("History.json", isDirectory: false)
        let text = String(repeating: "x", count: ClipboardCapture.inlineTextByteLimit + 1)
        let store = HistoryStore(
            blobStore: BlobStore(directoryURL: root.appendingPathComponent("Blobs", isDirectory: true)),
            preferences: PreferencesStore(
                fileURL: root.appendingPathComponent("Preferences.json", isDirectory: false)
            ),
            fileURL: historyURL
        )

        store.add(
            ClipboardCapture(
                kind: .plainText,
                title: text,
                textValue: nil,
                fileURLs: [],
                data: Data(text.utf8),
                byteCount: text.utf8.count,
                pasteboardTypeIdentifier: "public.utf8-plain-text"
            )
        )
        await store.flushPersistence()

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.title.count, ClipboardCapture.titlePreviewLimit)
        XCTAssertNil(item.textValue)
        XCTAssertNotNil(item.blobFilename)
        XCTAssertLessThan(try Data(contentsOf: historyURL).count, 4_096)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor SuspendedBlobStore: BlobStoring {
    static let filename = "84AF398F-98B5-43A9-9BC8-30A2488176D4.rtf"

    private var writeStarted = false
    private var writeContinuation: CheckedContinuation<Void, Never>?
    private var deleted: Set<String> = []

    func write(
        data: Data,
        fileExtension: String,
        pasteboardTypeIdentifier: String
    ) async throws -> BlobReference {
        writeStarted = true
        await withCheckedContinuation { continuation in
            writeContinuation = continuation
        }
        return BlobReference(
            filename: Self.filename,
            byteCount: data.count,
            pasteboardTypeIdentifier: pasteboardTypeIdentifier
        )
    }

    func read(filename: String) throws -> Data {
        Data()
    }

    func delete(filename: String) {
        deleted.insert(filename)
    }

    func clearAll() {}

    func sweep(keeping filenames: Set<String>) {}

    func waitUntilWriteStarts() async {
        while !writeStarted {
            await Task.yield()
        }
    }

    func resumeWrite() {
        let continuation = writeContinuation
        writeContinuation = nil
        continuation?.resume()
    }

    func deletedFilenames() -> Set<String> {
        deleted
    }
}
