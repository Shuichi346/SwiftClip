import AppKit
import XCTest
@testable import SwiftClip

@MainActor
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

    func testAddAttachmentFilesCopiesIntoManagedStorage() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Managed"))
        let fileURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        let imageData = Data("png".utf8)
        try imageData.write(to: fileURL, options: .atomic)

        let copiedAttachmentURLs = try store.addAttachmentFiles([fileURL], folderID: folderID, snippetID: snippetID)

        let copiedAttachmentURL = try XCTUnwrap(copiedAttachmentURLs.first.flatMap(URL.init(string:)))
        XCTAssertNotEqual(copiedAttachmentURL, fileURL)
        XCTAssertTrue(copiedAttachmentURL.path.hasPrefix(attachmentDirectoryURL.path + "/"))
        XCTAssertEqual(try Data(contentsOf: copiedAttachmentURL), imageData)

        let snippet = try XCTUnwrap(store.snippet(folderID: folderID, snippetID: snippetID))
        XCTAssertEqual(snippet.attachmentURLs, [copiedAttachmentURL.absoluteString])
    }

    func testRemoveAttachmentDeletesManagedCopy() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Managed"))
        let fileURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Data("png".utf8).write(to: fileURL, options: .atomic)
        let copiedAttachmentURL = try XCTUnwrap(
            try store.addAttachmentFiles([fileURL], folderID: folderID, snippetID: snippetID)
                .first
                .flatMap(URL.init(string:))
        )

        store.removeAttachmentURL(at: 0, folderID: folderID, snippetID: snippetID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedAttachmentURL.path))
        let snippet = try XCTUnwrap(store.snippet(folderID: folderID, snippetID: snippetID))
        XCTAssertEqual(snippet.attachmentURLs, [])
    }

    func testDeleteSnippetDeletesManagedCopy() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Managed"))
        let fileURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Data("png".utf8).write(to: fileURL, options: .atomic)
        let copiedAttachmentURL = try XCTUnwrap(
            try store.addAttachmentFiles([fileURL], folderID: folderID, snippetID: snippetID)
                .first
                .flatMap(URL.init(string:))
        )

        store.deleteSnippet(folderID: folderID, snippetID: snippetID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedAttachmentURL.path))
    }

    func testDeleteFolderDeletesManagedCopies() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Managed"))
        let fileURL = temporaryDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Data("png".utf8).write(to: fileURL, options: .atomic)
        let copiedAttachmentURL = try XCTUnwrap(
            try store.addAttachmentFiles([fileURL], folderID: folderID, snippetID: snippetID)
                .first
                .flatMap(URL.init(string:))
        )

        store.deleteFolder(id: folderID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedAttachmentURL.path))
    }

    func testDeleteSnippetDoesNotDeleteLegacyExternalAttachment() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let fileURL = temporaryDirectory.appendingPathComponent("external.png", isDirectory: false)
        try Data("png".utf8).write(to: fileURL, options: .atomic)
        let snippetID = try XCTUnwrap(
            store.addSnippet(to: folderID, title: "Legacy", attachmentURLs: [fileURL.absoluteString])
        )

        store.deleteSnippet(folderID: folderID, snippetID: snippetID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLargeFilesIncludesFiftyMegabyteFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("large.bin", isDirectory: false)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.truncate(atOffset: UInt64(SnippetAttachmentStore.largeFileWarningThresholdBytes))
        try fileHandle.close()

        let largeFiles = SnippetAttachmentStore.largeFiles(in: [fileURL])

        XCTAssertEqual(largeFiles, [
            SnippetAttachmentFileInfo(
                url: fileURL,
                byteCount: SnippetAttachmentStore.largeFileWarningThresholdBytes
            ),
        ])
    }

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
