import AppKit
import XCTest
@testable import SwiftClip

final class SnippetAttachmentTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        NSPasteboard.general.clearContents()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    @MainActor
    func testLoadTreatsMissingAttachmentURLsAsEmpty() throws {
        let snippetsURL = temporaryDirectory.appendingPathComponent("Snippets.json", isDirectory: false)
        let json = """
        [
          {
            "id": "7EF784BB-6224-446C-A4C3-62FD73C2F4DB",
            "title": "Folder",
            "sortIndex": 0,
            "isEnabled": true,
            "snippets": [
              {
                "id": "A57AC858-D7BC-4EB3-9547-93D9A4E241B6",
                "title": "Legacy",
                "content": "Text only",
                "sortIndex": 0,
                "isEnabled": true
              }
            ]
          }
        ]
        """
        try Data(json.utf8).write(to: snippetsURL, options: .atomic)

        let store = SnippetStore(fileURL: snippetsURL)
        store.load()

        let folder = try XCTUnwrap(store.allFolders().first)
        let snippet = try XCTUnwrap(folder.snippets.first)
        XCTAssertEqual(snippet.content, "Text only")
        XCTAssertEqual(snippet.attachmentURLs, [])
    }

    @MainActor
    func testAddAttachmentURLsKeepsFileURLsAndRemovesDuplicates() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Mixed"))
        let fileURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Data("png".utf8).write(to: fileURL, options: .atomic)

        store.addAttachmentURLs(
            [fileURL.absoluteString, "not-a-file-url", fileURL.absoluteString],
            folderID: folderID,
            snippetID: snippetID
        )

        let snippet = try XCTUnwrap(store.snippet(folderID: folderID, snippetID: snippetID))
        XCTAssertEqual(snippet.attachmentURLs, [fileURL.absoluteString])
    }

    @MainActor
    func testPasteSnippetWritesTextAndAttachmentsAsSeparatePasteboardItems() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("upload.txt", isDirectory: false)
        try Data("file".utf8).write(to: fileURL, options: .atomic)
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
        }
        let engine = PasteEngine(
            preferences: preferences,
            blobStore: BlobStore(directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true))
        )

        engine.paste(
            snippet: SnippetLeaf(
                title: "Mixed",
                content: "Prompt text",
                attachmentURLs: [fileURL.absoluteString]
            )
        )

        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]

        XCTAssertEqual(pasteboard.string(forType: .string), "Prompt text")
        XCTAssertEqual(urls?.map(\.absoluteString), [fileURL.absoluteString])

        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "Prompt text")
        XCTAssertEqual(items[1].string(forType: .fileURL), fileURL.absoluteString)
    }

    @MainActor
    func testPasteHistoryItemIgnoresInvalidFileURLs() async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
        }
        let engine = PasteEngine(
            preferences: preferences,
            blobStore: BlobStore(directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true))
        )
        var writeCount = 0
        engine.onPasteboardWrite = {
            writeCount += 1
        }

        engine.paste(
            item: ClipboardItem(
                kind: .fileURL,
                title: "Invalid file",
                fileURLs: ["https://example.com/not-a-file"],
                byteCount: 30,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }

    @MainActor
    private func makeStore() -> SnippetStore {
        SnippetStore(fileURL: temporaryDirectory.appendingPathComponent("Snippets.json"))
    }
}
