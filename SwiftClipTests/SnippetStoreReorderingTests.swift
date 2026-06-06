import XCTest
@testable import SwiftClip

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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testLoadNormalizesFolderAndSnippetSortIndexes() throws {
        let snippetsURL = temporaryDirectory.appendingPathComponent("Snippets.json", isDirectory: false)
        let firstFolderID = UUID()
        let secondFolderID = UUID()
        let lowSnippetID = UUID()
        let highSnippetID = UUID()
        let json = """
        [
          {
            "id": "\(secondFolderID.uuidString)",
            "title": "Second",
            "sortIndex": 1,
            "isEnabled": true,
            "snippets": []
          },
          {
            "id": "\(firstFolderID.uuidString)",
            "title": "First",
            "sortIndex": 0,
            "isEnabled": true,
            "snippets": [
              {
                "id": "\(highSnippetID.uuidString)",
                "title": "High",
                "content": "",
                "attachmentURLs": [],
                "sortIndex": 9,
                "isEnabled": true
              },
              {
                "id": "\(lowSnippetID.uuidString)",
                "title": "Low",
                "content": "",
                "attachmentURLs": [],
                "sortIndex": 2,
                "isEnabled": true
              }
            ]
          }
        ]
        """
        try Data(json.utf8).write(to: snippetsURL, options: .atomic)

        let store = SnippetStore(fileURL: snippetsURL)
        store.load()

        let folders = store.allFolders()
        XCTAssertEqual(folders.map(\.id), [firstFolderID, secondFolderID])
        XCTAssertEqual(folders.map(\.sortIndex), [0, 1])
        XCTAssertEqual(folders.first?.snippets.map(\.id), [lowSnippetID, highSnippetID])
        XCTAssertEqual(folders.first?.snippets.map(\.sortIndex), [0, 1])
    }

    @MainActor
    private func makeStore() -> SnippetStore {
        SnippetStore(fileURL: temporaryDirectory.appendingPathComponent("Snippets.json"))
    }
}
