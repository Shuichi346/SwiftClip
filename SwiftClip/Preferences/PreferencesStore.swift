import Combine
import Foundation
import ServiceManagement
import SwiftUI
import SwiftData

struct PreferencesState: Codable, Equatable, Sendable {
    var launchAtLogin = false
    var pasteAfterSelection = true
    var showNumbers = true
    var startNumbersAtZero = false
    var historyLimit = 5
    var menuTitleCharacterLimit = 30
    var formatPlainText = true
    var formatRTF = true
    var formatRTFD = true
    var formatFileURL = true
    var formatURL = true
    var formatPDF = false
    var formatImage = false
    var excludedBundleIDs: [String] = []
    var mixedSnippetPasteBundleIDs = Self.defaultMixedSnippetPasteBundleIDs

    static let maximumHistoryLimit = 50
    static let maximumPayloadBytes = 50 * 1024 * 1024
    static let defaultMixedSnippetPasteBundleIDs: [String] = []
    private static let legacyDefaultMixedSnippetPasteBundleIDs = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.thebrowser.Browser",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
    ]

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case pasteAfterSelection
        case showNumbers
        case startNumbersAtZero
        case historyLimit
        case menuTitleCharacterLimit
        case formatPlainText
        case formatRTF
        case formatRTFD
        case formatFileURL
        case formatURL
        case formatPDF
        case formatImage
        case excludedBundleIDs
        case mixedSnippetPasteBundleIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        pasteAfterSelection = try container.decodeIfPresent(Bool.self, forKey: .pasteAfterSelection) ?? true
        showNumbers = try container.decodeIfPresent(Bool.self, forKey: .showNumbers) ?? true
        startNumbersAtZero = try container.decodeIfPresent(Bool.self, forKey: .startNumbersAtZero) ?? false
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 5
        menuTitleCharacterLimit = try container.decodeIfPresent(Int.self, forKey: .menuTitleCharacterLimit) ?? 30
        formatPlainText = try container.decodeIfPresent(Bool.self, forKey: .formatPlainText) ?? true
        formatRTF = try container.decodeIfPresent(Bool.self, forKey: .formatRTF) ?? true
        formatRTFD = try container.decodeIfPresent(Bool.self, forKey: .formatRTFD) ?? true
        formatFileURL = try container.decodeIfPresent(Bool.self, forKey: .formatFileURL) ?? true
        formatURL = try container.decodeIfPresent(Bool.self, forKey: .formatURL) ?? true
        formatPDF = try container.decodeIfPresent(Bool.self, forKey: .formatPDF) ?? false
        formatImage = try container.decodeIfPresent(Bool.self, forKey: .formatImage) ?? false
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
        mixedSnippetPasteBundleIDs = Self.normalizedMixedSnippetPasteBundleIDs(try container.decodeIfPresent(
            [String].self,
            forKey: .mixedSnippetPasteBundleIDs
        ))
    }

    private static func normalizedMixedSnippetPasteBundleIDs(_ bundleIDs: [String]?) -> [String] {
        guard let bundleIDs else {
            return defaultMixedSnippetPasteBundleIDs
        }

        if Set(bundleIDs) == Set(legacyDefaultMixedSnippetPasteBundleIDs),
           bundleIDs.count == legacyDefaultMixedSnippetPasteBundleIDs.count {
            return defaultMixedSnippetPasteBundleIDs
        }

        return bundleIDs
    }
}

@Model
final class PreferencesRecord {
    @Attribute(.unique) var key: String
    var jsonData: Data?

    init(key: String = "default", jsonData: Data? = nil) {
        self.key = key
        self.jsonData = jsonData
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var state = PreferencesState()

    private let fileURL: URL
    private let persistenceQueue = JSONPersistenceQueue(label: "app.swiftclip.preferences.persistence")

    init(fileURL: URL = FileLocations.preferencesURL) {
        self.fileURL = fileURL
    }

    func load() {
        do {
            try FileLocations.ensureBaseDirectories()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                persist()
                return
            }

            let data = try Data(contentsOf: fileURL)
            var decoded = try JSONDecoder().decode(PreferencesState.self, from: data)
            decoded.historyLimit = clampedHistoryLimit(decoded.historyLimit)
            decoded.menuTitleCharacterLimit = max(5, decoded.menuTitleCharacterLimit)
            state = decoded
        } catch {
            AppLog.preferences.error("Could not load preferences: \(error.localizedDescription, privacy: .public)")
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<PreferencesState, Value>) -> Binding<Value> {
        Binding {
            self.state[keyPath: keyPath]
        } set: { newValue in
            self.update { preferences in
                preferences[keyPath: keyPath] = newValue
            }
        }
    }

    func update(_ mutate: (inout PreferencesState) -> Void) {
        var nextState = state
        mutate(&nextState)
        nextState.historyLimit = clampedHistoryLimit(nextState.historyLimit)
        nextState.menuTitleCharacterLimit = max(5, nextState.menuTitleCharacterLimit)
        state = nextState
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        update { preferences in
            preferences.launchAtLogin = enabled
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.preferences.error("Could not update launch-at-login registration: \(error.localizedDescription, privacy: .public)")
        }
    }

    func addExcludedBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        update { preferences in
            if !preferences.excludedBundleIDs.contains(trimmed) {
                preferences.excludedBundleIDs.append(trimmed)
                preferences.excludedBundleIDs.sort()
            }
        }
    }

    func removeExcludedBundleID(_ bundleID: String) {
        update { preferences in
            preferences.excludedBundleIDs.removeAll { $0 == bundleID }
        }
    }

    func addMixedSnippetPasteBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        update { preferences in
            if !preferences.mixedSnippetPasteBundleIDs.contains(trimmed) {
                preferences.mixedSnippetPasteBundleIDs.append(trimmed)
                preferences.mixedSnippetPasteBundleIDs.sort()
            }
        }
    }

    func removeMixedSnippetPasteBundleID(_ bundleID: String) {
        update { preferences in
            preferences.mixedSnippetPasteBundleIDs.removeAll { $0 == bundleID }
        }
    }

    func shouldCapture(bundleID: String?) -> Bool {
        guard let bundleID else {
            return true
        }

        return !state.excludedBundleIDs.contains(bundleID)
    }

    func shouldUseTwoStepMixedSnippetPaste(bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }

        return state.mixedSnippetPasteBundleIDs.contains(bundleID)
    }

    private func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(1, value), PreferencesState.maximumHistoryLimit)
    }

    private func persist() {
        persistenceQueue.write(state, to: fileURL) { error in
            AppLog.preferences.error("Could not persist preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}
