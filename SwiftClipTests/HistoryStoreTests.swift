import XCTest
@testable import SwiftClip

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testLoadDecodesPersistedISO8601Dates() throws {
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
        store.load()

        XCTAssertEqual(store.items, [item])
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
