import XCTest
@testable import SwiftClip

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testDefaultsKeepImagesAndPDFDisabled() {
        let state = PreferencesState()

        XCTAssertFalse(state.formatImage)
        XCTAssertFalse(state.formatPDF)
        XCTAssertEqual(state.historyLimit, 5)
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
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let restored = PreferencesStore(fileURL: url)
        restored.load()

        XCTAssertEqual(restored.state.historyLimit, 12)
        XCTAssertTrue(restored.state.formatImage)
        XCTAssertEqual(restored.state.excludedBundleIDs, ["com.example.PasswordVault"])
    }
}
