import AppKit
import XCTest
@testable import SwiftClip

final class SnippetAttachmentTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

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
    func testLoadTreatsMissingAttachmentURLsAsEmpty() async throws {
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
        await store.load()

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
    func testRemovingAttachmentDeletesManagedFileOnlyAfterLastReference() async throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let firstSnippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "First"))
        let secondSnippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Second"))
        let sourceURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Data("png".utf8).write(to: sourceURL, options: .atomic)

        let managedAttachmentURLs = try await store.addAttachmentFiles(
            [sourceURL],
            folderID: folderID,
            snippetID: firstSnippetID
        )
        let managedAttachmentURL = try XCTUnwrap(managedAttachmentURLs.first)
        let managedFileURL = try XCTUnwrap(URL(string: managedAttachmentURL))
        store.addAttachmentURLs([managedAttachmentURL], folderID: folderID, snippetID: secondSnippetID)

        store.removeAttachmentURL(at: 0, folderID: folderID, snippetID: firstSnippetID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: managedFileURL.path))

        store.removeAttachmentURL(at: 0, folderID: folderID, snippetID: secondSnippetID)
        store.flushPersistence()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedFileURL.path))
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
    func testAlwaysPasteAsPlainTextOmitsSnippetAttachments() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("upload.txt", isDirectory: false)
        try Data("file".utf8).write(to: fileURL, options: .atomic)
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
            state.alwaysPasteAsPlainText = true
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
        XCTAssertTrue(urls?.isEmpty ?? true)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
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
        engine.onPasteboardWrite = { _ in
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
    func testPasteEmptySnippetPreservesExistingClipboard() {
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
        engine.onPasteboardWrite = { _ in
            writeCount += 1
        }

        engine.paste(snippet: SnippetLeaf(title: "Empty", content: ""))

        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }

    @MainActor
    func testPlainTextPasteConvertsRichHistoryBlob() async throws {
        let attributedString = NSAttributedString(string: "Styled clipboard text")
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let blobStore = BlobStore(
            directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true)
        )
        let reference = try await blobStore.write(
            data: rtfData,
            fileExtension: "rtf",
            pasteboardTypeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue
        )
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
            state.alwaysPasteAsPlainText = true
        }
        let engine = PasteEngine(preferences: preferences, blobStore: blobStore)
        let writeExpectation = expectation(description: "Plain-text pasteboard write")
        engine.onPasteboardWrite = { _ in
            writeExpectation.fulfill()
        }

        engine.paste(
            item: ClipboardItem(
                kind: .richText,
                title: "Rich text",
                blobFilename: reference.filename,
                byteCount: rtfData.count,
                pasteboardTypeIdentifier: reference.pasteboardTypeIdentifier
            )
        )

        await fulfillment(of: [writeExpectation], timeout: 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Styled clipboard text")
        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
    }

    @MainActor
    func testDefaultPastePreservesRichHistoryBlob() async throws {
        let attributedString = NSAttributedString(string: "Styled clipboard text")
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let blobStore = BlobStore(
            directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true)
        )
        let reference = try await blobStore.write(
            data: rtfData,
            fileExtension: "rtf",
            pasteboardTypeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue
        )
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
        }
        let engine = PasteEngine(preferences: preferences, blobStore: blobStore)
        let writeExpectation = expectation(description: "Rich-text pasteboard write")
        engine.onPasteboardWrite = { _ in
            writeExpectation.fulfill()
        }

        engine.paste(
            item: ClipboardItem(
                kind: .richText,
                title: "Styled clipboard text",
                blobFilename: reference.filename,
                byteCount: rtfData.count,
                pasteboardTypeIdentifier: reference.pasteboardTypeIdentifier
            )
        )

        await fulfillment(of: [writeExpectation], timeout: 1)
        XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), rtfData)
    }

    @MainActor
    func testAlwaysPasteAsPlainTextConvertsHTMLHistoryBlob() async throws {
        let htmlData = Data("<html><body><strong>Styled</strong> clipboard text</body></html>".utf8)
        let blobStore = BlobStore(
            directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true)
        )
        let reference = try await blobStore.write(
            data: htmlData,
            fileExtension: "html",
            pasteboardTypeIdentifier: NSPasteboard.PasteboardType.html.rawValue
        )
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
            state.alwaysPasteAsPlainText = true
        }
        let engine = PasteEngine(preferences: preferences, blobStore: blobStore)
        let writeExpectation = expectation(description: "HTML converted to plain-text pasteboard write")
        engine.onPasteboardWrite = { _ in
            writeExpectation.fulfill()
        }

        engine.paste(
            item: ClipboardItem(
                kind: .html,
                title: "Styled clipboard text",
                blobFilename: reference.filename,
                byteCount: htmlData.count,
                pasteboardTypeIdentifier: reference.pasteboardTypeIdentifier
            )
        )

        await fulfillment(of: [writeExpectation], timeout: 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Styled clipboard text")
        XCTAssertNil(NSPasteboard.general.data(forType: .html))
    }

    @MainActor
    func testDefaultPastePreservesHTMLHistoryBlob() async throws {
        let htmlData = Data("<html><body><strong>Styled</strong> clipboard text</body></html>".utf8)
        let blobStore = BlobStore(
            directoryURL: temporaryDirectory.appendingPathComponent("Blobs", isDirectory: true)
        )
        let reference = try await blobStore.write(
            data: htmlData,
            fileExtension: "html",
            pasteboardTypeIdentifier: NSPasteboard.PasteboardType.html.rawValue
        )
        let preferences = PreferencesStore(fileURL: temporaryDirectory.appendingPathComponent("Preferences.json"))
        preferences.update { state in
            state.pasteAfterSelection = false
        }
        let engine = PasteEngine(preferences: preferences, blobStore: blobStore)
        let writeExpectation = expectation(description: "HTML pasteboard write")
        engine.onPasteboardWrite = { _ in
            writeExpectation.fulfill()
        }

        engine.paste(
            item: ClipboardItem(
                kind: .html,
                title: "Styled clipboard text",
                blobFilename: reference.filename,
                byteCount: htmlData.count,
                pasteboardTypeIdentifier: reference.pasteboardTypeIdentifier
            )
        )

        await fulfillment(of: [writeExpectation], timeout: 1)
        XCTAssertEqual(NSPasteboard.general.data(forType: .html), htmlData)
    }

    @MainActor
    private func makeStore() -> SnippetStore {
        SnippetStore(
            fileURL: temporaryDirectory.appendingPathComponent("Snippets.json"),
            attachmentDirectoryURL: attachmentDirectoryURL
        )
    }

    private var attachmentDirectoryURL: URL {
        temporaryDirectory.appendingPathComponent("SnippetAttachments", isDirectory: true)
    }
}
