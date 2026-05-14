import XCTest
@testable import SwiftClip

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testDefaultsKeepImagesAndPDFDisabled() {
        let state = PreferencesState()

        XCTAssertFalse(state.formatImage)
        XCTAssertFalse(state.formatPDF)
        XCTAssertEqual(state.historyLimit, 5)
        XCTAssertTrue(state.mixedSnippetPasteBundleIDs.contains("com.google.Chrome"))
        XCTAssertTrue(state.mixedSnippetPasteBundleIDs.contains("com.apple.Safari"))
    }

    func testPreferenceRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = PreferencesStore(fileURL: url)
        store.update { preferences in
            preferences.historyLimit = 12
            preferences.formatImage = true
            preferences.excludedBundleIDs = ["com.example.PasswordVault"]
            preferences.mixedSnippetPasteBundleIDs = ["com.example.Chat"]
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let restored = PreferencesStore(fileURL: url)
        restored.load()

        XCTAssertEqual(restored.state.historyLimit, 12)
        XCTAssertTrue(restored.state.formatImage)
        XCTAssertEqual(restored.state.excludedBundleIDs, ["com.example.PasswordVault"])
        XCTAssertEqual(restored.state.mixedSnippetPasteBundleIDs, ["com.example.Chat"])
    }

    func testLoadLegacyPreferencesUsesDefaultMixedSnippetPasteApps() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let json = """
        {
          "historyLimit" : 8,
          "formatImage" : true,
          "excludedBundleIDs" : [
            "com.example.PasswordVault"
          ]
        }
        """
        try Data(json.utf8).write(to: url, options: .atomic)

        let store = PreferencesStore(fileURL: url)
        store.load()

        XCTAssertEqual(store.state.historyLimit, 8)
        XCTAssertTrue(store.state.formatImage)
        XCTAssertEqual(store.state.excludedBundleIDs, ["com.example.PasswordVault"])
        XCTAssertEqual(
            store.state.mixedSnippetPasteBundleIDs,
            PreferencesState.defaultMixedSnippetPasteBundleIDs
        )
    }

    func testMixedSnippetPasteBundleIDsTrimSortAndRemoveDuplicates() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = PreferencesStore(fileURL: url)

        store.update { preferences in
            preferences.mixedSnippetPasteBundleIDs = []
        }
        store.addMixedSnippetPasteBundleID("  com.example.Chat  ")
        store.addMixedSnippetPasteBundleID("com.example.Editor")
        store.addMixedSnippetPasteBundleID("com.example.Chat")

        XCTAssertEqual(store.state.mixedSnippetPasteBundleIDs, ["com.example.Chat", "com.example.Editor"])
        XCTAssertTrue(store.shouldUseTwoStepMixedSnippetPaste(bundleID: "com.example.Chat"))

        store.removeMixedSnippetPasteBundleID("com.example.Chat")

        XCTAssertEqual(store.state.mixedSnippetPasteBundleIDs, ["com.example.Editor"])
        XCTAssertFalse(store.shouldUseTwoStepMixedSnippetPaste(bundleID: "com.example.Chat"))
        XCTAssertFalse(store.shouldUseTwoStepMixedSnippetPaste(bundleID: nil))
    }
}
