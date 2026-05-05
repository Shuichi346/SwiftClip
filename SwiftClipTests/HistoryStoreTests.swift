import XCTest
@testable import SwiftClip

@MainActor
final class HistoryStoreTests: XCTestCase {
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
