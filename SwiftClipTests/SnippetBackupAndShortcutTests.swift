import AppKit
import KeyboardShortcuts
import XCTest
@testable import SwiftClip

@MainActor
final class SnippetBackupAndShortcutTests: XCTestCase {
    func testReplaceBackupRestoresCompleteLibrary() async throws {
        let root = try temporaryDirectory()
        let snippetsURL = root.appendingPathComponent("Snippets.json", isDirectory: false)
        let attachmentDirectory = root.appendingPathComponent("Attachments", isDirectory: true)
        let backupDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)

        let attachmentURL = attachmentDirectory.appendingPathComponent("reference.txt", isDirectory: false)
        let attachmentData = Data("attachment payload".utf8)
        try attachmentData.write(to: attachmentURL, options: .atomic)

        let store = SnippetStore(
            fileURL: snippetsURL,
            attachmentDirectoryURL: attachmentDirectory,
            backupDirectoryURL: backupDirectory
        )
        await store.load()
        let folderID = store.addFolder(title: "Original folder")
        let snippetID = try XCTUnwrap(
            store.addSnippet(
                to: folderID,
                title: "Original snippet",
                content: "Original content",
                attachmentURLs: [attachmentURL.absoluteString]
            )
        )
        store.updateFolder(id: folderID, isEnabled: false)
        store.updateSnippet(folderID: folderID, snippetID: snippetID, isEnabled: false)
        store.flushPersistence()

        let folderName = KeyboardShortcuts.Name.folder(folderID)
        let snippetName = KeyboardShortcuts.Name.snippet(snippetID)
        let folderShortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .option, .control])
        let snippetShortcut = KeyboardShortcuts.Shortcut(.b, modifiers: [.command, .option, .control])
        KeyboardShortcuts.setShortcut(folderShortcut, for: folderName)
        KeyboardShortcuts.setShortcut(snippetShortcut, for: snippetName)
        defer {
            KeyboardShortcuts.setShortcut(nil, for: folderName)
            KeyboardShortcuts.setShortcut(nil, for: snippetName)
        }
        let originalFolders = store.allFolders()

        try await store.replaceAll(
            with: [SnippetSummary(title: "Imported", snippets: [SnippetLeaf(title: "New", content: "New")])]
        )

        XCTAssertNil(KeyboardShortcuts.getShortcut(for: folderName))
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: snippetName))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentURL.path))
        let backupURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: nil
            ).first { $0.pathExtension == SnippetLibraryBackupStore.fileExtension }
        )

        try await store.restoreBackup(from: backupURL)

        XCTAssertEqual(store.allFolders(), originalFolders)
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: folderName), folderShortcut)
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: snippetName), snippetShortcut)
        XCTAssertEqual(try Data(contentsOf: attachmentURL), attachmentData)
    }

    func testReplaceDoesNotMutateLibraryWhenBackupFails() async throws {
        let root = try temporaryDirectory()
        let attachmentDirectory = root.appendingPathComponent("Attachments", isDirectory: true)
        let missingAttachmentURL = attachmentDirectory.appendingPathComponent("missing.txt", isDirectory: false)
        let store = SnippetStore(
            fileURL: root.appendingPathComponent("Snippets.json", isDirectory: false),
            attachmentDirectoryURL: attachmentDirectory,
            backupDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true)
        )
        await store.load()
        let folderID = store.addFolder(title: "Keep me")
        _ = store.addSnippet(
            to: folderID,
            title: "Keep me too",
            content: "Content",
            attachmentURLs: [missingAttachmentURL.absoluteString]
        )
        let originalFolders = store.allFolders()

        do {
            try await store.replaceAll(with: [])
            XCTFail("Expected backup creation to fail")
        } catch let error as SwiftClipError {
            guard case .snippetBackupFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(store.allFolders(), originalFolders)
    }

    func testBackupAttachmentsRestoreIntoTheCurrentManagedDirectory() async throws {
        let root = try temporaryDirectory()
        let sourceAttachmentDirectory = root.appendingPathComponent("SourceAttachments", isDirectory: true)
        let restoredAttachmentDirectory = root.appendingPathComponent("RestoredAttachments", isDirectory: true)
        let backupDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceAttachmentDirectory,
            withIntermediateDirectories: true
        )
        let sourceURL = sourceAttachmentDirectory.appendingPathComponent("portable.txt", isDirectory: false)
        let payload = Data("portable attachment".utf8)
        try payload.write(to: sourceURL, options: .atomic)
        let folders = [
            SnippetSummary(
                title: "Folder",
                snippets: [
                    SnippetLeaf(
                        title: "Snippet",
                        content: "Content",
                        attachmentURLs: [sourceURL.absoluteString]
                    ),
                ]
            ),
        ]
        let sourceStore = SnippetLibraryBackupStore(
            backupDirectoryURL: backupDirectory,
            attachmentDirectoryURL: sourceAttachmentDirectory
        )
        let backupURL = try await sourceStore.createBackup(folders: folders, shortcuts: [])
        try FileManager.default.removeItem(at: sourceAttachmentDirectory)

        let restoreStore = SnippetLibraryBackupStore(
            backupDirectoryURL: backupDirectory,
            attachmentDirectoryURL: restoredAttachmentDirectory
        )
        let restore = try await restoreStore.prepareRestore(from: backupURL)
        let restoredURLString = try XCTUnwrap(restore.folders.first?.snippets.first?.attachmentURLs.first)
        let restoredURL = try XCTUnwrap(URL(string: restoredURLString))

        XCTAssertEqual(restoredURL.deletingLastPathComponent(), restoredAttachmentDirectory)
        XCTAssertEqual(try Data(contentsOf: restoredURL), payload)
    }

    func testLegacyDynamicShortcutMigratesToDotFreeName() {
        let folderID = UUID()
        let canonicalName = KeyboardShortcuts.Name.folder(folderID)
        let legacyName = KeyboardShortcuts.Name.legacyFolder(folderID)
        let shortcut = KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .option, .control])
        KeyboardShortcuts.setShortcut(nil, for: canonicalName)
        KeyboardShortcuts.setShortcut(shortcut, for: legacyName)
        defer {
            KeyboardShortcuts.setShortcut(nil, for: canonicalName)
            KeyboardShortcuts.setShortcut(nil, for: legacyName)
        }

        SnippetShortcutStorage.migrateAndPrune(
            folders: [SnippetSummary(id: folderID, title: "Folder")]
        )

        XCTAssertFalse(canonicalName.rawValue.contains("."))
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: canonicalName), shortcut)
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: legacyName))
    }

    func testDeletingEntitiesClearsShortcutsAfterPersistence() async throws {
        let root = try temporaryDirectory()
        let store = SnippetStore(
            fileURL: root.appendingPathComponent("Snippets.json", isDirectory: false),
            attachmentDirectoryURL: root.appendingPathComponent("Attachments", isDirectory: true),
            backupDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true)
        )
        await store.load()
        let folderID = store.addFolder(title: "Folder")
        let snippetID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Snippet"))
        let folderName = KeyboardShortcuts.Name.folder(folderID)
        let snippetName = KeyboardShortcuts.Name.snippet(snippetID)
        KeyboardShortcuts.setShortcut(
            KeyboardShortcuts.Shortcut(.d, modifiers: [.command, .option, .control]),
            for: folderName
        )
        KeyboardShortcuts.setShortcut(
            KeyboardShortcuts.Shortcut(.e, modifiers: [.command, .option, .control]),
            for: snippetName
        )
        defer {
            KeyboardShortcuts.setShortcut(nil, for: folderName)
            KeyboardShortcuts.setShortcut(nil, for: snippetName)
        }

        store.deleteSnippet(folderID: folderID, snippetID: snippetID)
        store.flushPersistence()
        await waitUntilShortcutIsRemoved(snippetName)
        XCTAssertNotNil(KeyboardShortcuts.getShortcut(for: folderName))

        store.deleteFolder(id: folderID)
        store.flushPersistence()
        await waitUntilShortcutIsRemoved(folderName)
    }

    private func waitUntilShortcutIsRemoved(_ name: KeyboardShortcuts.Name) async {
        for _ in 0..<100 where KeyboardShortcuts.getShortcut(for: name) != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
