import XCTest
@testable import SwiftClip

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testDefaultsKeepImagesAndPDFDisabled() {
        let state = PreferencesState()

        XCTAssertFalse(state.formatImage)
        XCTAssertFalse(state.formatPDF)
        XCTAssertFalse(state.alwaysPasteAsPlainText)
        XCTAssertEqual(state.historyLimit, 5)
        XCTAssertEqual(state.mixedSnippetPasteBundleIDs, [])
    }

    func testPreferenceRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = PreferencesStore(fileURL: url)
        store.update { preferences in
            preferences.historyLimit = 12
            preferences.formatImage = true
            preferences.alwaysPasteAsPlainText = true
            preferences.excludedBundleIDs = ["com.example.PasswordVault"]
            preferences.mixedSnippetPasteBundleIDs = ["com.example.Chat"]
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let restored = PreferencesStore(fileURL: url)
        await restored.load()

        XCTAssertEqual(restored.state.historyLimit, 12)
        XCTAssertTrue(restored.state.formatImage)
        XCTAssertTrue(restored.state.alwaysPasteAsPlainText)
        XCTAssertEqual(restored.state.excludedBundleIDs, ["com.example.PasswordVault"])
        XCTAssertEqual(restored.state.mixedSnippetPasteBundleIDs, ["com.example.Chat"])
    }

    func testLoadLegacyPreferencesLeavesMixedSnippetPasteAppsEmpty() async throws {
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
        await store.load()

        XCTAssertEqual(store.state.historyLimit, 8)
        XCTAssertTrue(store.state.formatImage)
        XCTAssertFalse(store.state.alwaysPasteAsPlainText)
        XCTAssertEqual(store.state.excludedBundleIDs, ["com.example.PasswordVault"])
        XCTAssertEqual(
            store.state.mixedSnippetPasteBundleIDs,
            PreferencesState.defaultMixedSnippetPasteBundleIDs
        )
    }

    func testLoadLegacyBrowserDefaultsLeavesMixedSnippetPasteAppsEmpty() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let json = """
        {
          "mixedSnippetPasteBundleIDs" : [
            "com.apple.Safari",
            "com.brave.Browser",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.thebrowser.Browser",
            "company.thebrowser.Browser",
            "org.mozilla.firefox"
          ]
        }
        """
        try Data(json.utf8).write(to: url, options: .atomic)

        let store = PreferencesStore(fileURL: url)
        await store.load()

        XCTAssertEqual(store.state.mixedSnippetPasteBundleIDs, [])
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

    func testLaunchAtLoginFailureDoesNotChangeOrPersistPreference() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try JSONEncoder().encode(PreferencesState()).write(to: url, options: .atomic)
        let controller = FailingLaunchAtLoginController(isEnabled: false)
        let store = PreferencesStore(
            fileURL: url,
            launchAtLoginController: controller
        )
        await store.load()

        XCTAssertThrowsError(try store.setLaunchAtLogin(true))
        store.flushPersistence()

        XCTAssertFalse(store.state.launchAtLogin)
        XCTAssertFalse(controller.isEnabled)
        let persisted = try JSONDecoder().decode(
            PreferencesState.self,
            from: Data(contentsOf: url)
        )
        XCTAssertFalse(persisted.launchAtLogin)
    }
}

@MainActor
private final class FailingLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        throw TestError.registrationFailed
    }

    private enum TestError: Error {
        case registrationFailed
    }
}
