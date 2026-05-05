import XCTest
@testable import SwiftClip

@MainActor
final class SnippetStoreReorderingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testMoveFoldersReordersSortIndexes() {
        let store = makeStore()
        store.addFolder(title: "A")
        store.addFolder(title: "B")
        store.addFolder(title: "C")

        store.moveFolders(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let folders = store.allFolders()
        XCTAssertEqual(folders.map(\.title), ["B", "C", "A"])
        XCTAssertEqual(folders.map(\.sortIndex), [0, 1, 2])
    }

    func testMoveSnippetsWithinFolderReordersSortIndexes() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let firstID = try XCTUnwrap(store.addSnippet(to: folderID, title: "One"))
        let secondID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Two"))

        store.moveSnippets(in: folderID, fromOffsets: IndexSet(integer: 0), toOffset: 2)

        let snippets = try XCTUnwrap(store.folder(id: folderID)?.snippets.sorted { $0.sortIndex < $1.sortIndex })
        XCTAssertEqual(snippets.map(\.id), [secondID, firstID])
        XCTAssertEqual(snippets.map(\.sortIndex), [0, 1])
    }

    func testMoveSnippetWithinSameFolderWithoutDestinationMovesToEnd() throws {
        let store = makeStore()
        let folderID = store.addFolder(title: "Folder")
        let firstID = try XCTUnwrap(store.addSnippet(to: folderID, title: "One"))
        let secondID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Two"))
        let thirdID = try XCTUnwrap(store.addSnippet(to: folderID, title: "Three"))

        store.moveSnippet(snippetID: firstID, fromFolderID: folderID, toFolderID: folderID)

        let snippets = try XCTUnwrap(store.folder(id: folderID)?.snippets.sorted { $0.sortIndex < $1.sortIndex })
        XCTAssertEqual(snippets.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(snippets.map(\.sortIndex), [0, 1, 2])
    }

    func testMoveSnippetBetweenFoldersInsertsAtRequestedIndex() throws {
        let store = makeStore()
        let sourceFolderID = store.addFolder(title: "Source")
        let targetFolderID = store.addFolder(title: "Target")
        let movedID = try XCTUnwrap(store.addSnippet(to: sourceFolderID, title: "Move Me", content: "Payload"))
        let remainingID = try XCTUnwrap(store.addSnippet(to: sourceFolderID, title: "Stay"))
        let existingID = try XCTUnwrap(store.addSnippet(to: targetFolderID, title: "Existing"))

        store.moveSnippet(
            snippetID: movedID,
            fromFolderID: sourceFolderID,
            toFolderID: targetFolderID,
            toIndex: 0
        )

        let sourceSnippets = try XCTUnwrap(store.folder(id: sourceFolderID)?.snippets.sorted { $0.sortIndex < $1.sortIndex })
        let targetSnippets = try XCTUnwrap(store.folder(id: targetFolderID)?.snippets.sorted { $0.sortIndex < $1.sortIndex })

        XCTAssertEqual(sourceSnippets.map(\.id), [remainingID])
        XCTAssertEqual(sourceSnippets.map(\.sortIndex), [0])
        XCTAssertEqual(targetSnippets.map(\.id), [movedID, existingID])
        XCTAssertEqual(targetSnippets.map(\.sortIndex), [0, 1])
        XCTAssertEqual(targetSnippets.first?.content, "Payload")
    }

    private func makeStore() -> SnippetStore {
        SnippetStore(fileURL: temporaryDirectory.appendingPathComponent("Snippets.json"))
    }
}
