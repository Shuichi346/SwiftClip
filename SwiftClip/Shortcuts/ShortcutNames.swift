import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let mainMenu = Self("mainMenu")
    static let clearHistory = Self("clearHistory")
    static let snippetEditor = Self("snippetEditor")
    static let preferences = Self("preferences")
    static let plainTextPaste = Self("plainTextPaste")

    static func snippet(_ id: UUID) -> Self {
        Self("snippet-\(id.uuidString)")
    }

    static func folder(_ id: UUID) -> Self {
        Self("folder-\(id.uuidString)")
    }

    static func legacySnippet(_ id: UUID) -> Self {
        Self(rawValue: "snippet.\(id.uuidString)")!
    }

    static func legacyFolder(_ id: UUID) -> Self {
        Self(rawValue: "folder.\(id.uuidString)")!
    }
}

@MainActor
enum SnippetShortcutStorage {
    static func backupRecords(for folders: [SnippetSummary]) -> [SnippetShortcutBackupRecord] {
        var records: [SnippetShortcutBackupRecord] = []
        for folder in folders {
            if let shortcut = shortcut(canonical: .folder(folder.id), legacy: .legacyFolder(folder.id)) {
                records.append(
                    .init(entityKind: .folder, entityID: folder.id, shortcut: shortcut)
                )
            }

            for snippet in folder.snippets {
                if let shortcut = shortcut(canonical: .snippet(snippet.id), legacy: .legacySnippet(snippet.id)) {
                    records.append(
                        .init(entityKind: .snippet, entityID: snippet.id, shortcut: shortcut)
                    )
                }
            }
        }
        return records
    }

    static func migrateAndPrune(folders: [SnippetSummary]) {
        let folderIDs = Set(folders.map(\.id))
        let snippetIDs = Set(folders.flatMap { $0.snippets.map(\.id) })

        for folderID in folderIDs {
            migrate(canonical: .folder(folderID), legacy: .legacyFolder(folderID))
        }
        for snippetID in snippetIDs {
            migrate(canonical: .snippet(snippetID), legacy: .legacySnippet(snippetID))
        }

        for name in KeyboardShortcuts.storedNames {
            guard let entity = dynamicEntity(from: name.rawValue) else {
                continue
            }

            let isActive: Bool
            switch entity {
            case .folder(let id):
                isActive = folderIDs.contains(id)
            case .snippet(let id):
                isActive = snippetIDs.contains(id)
            }

            if !isActive || name.rawValue.contains(".") {
                KeyboardShortcuts.setShortcut(nil, for: name)
            }
        }
    }

    static func removeShortcuts(removedFrom oldFolders: [SnippetSummary], retainedIn newFolders: [SnippetSummary]) {
        let retainedFolderIDs = Set(newFolders.map(\.id))
        let retainedSnippetIDs = Set(newFolders.flatMap { $0.snippets.map(\.id) })

        for folder in oldFolders where !retainedFolderIDs.contains(folder.id) {
            clear(canonical: .folder(folder.id), legacy: .legacyFolder(folder.id))
        }
        for snippet in oldFolders.flatMap(\.snippets) where !retainedSnippetIDs.contains(snippet.id) {
            clear(canonical: .snippet(snippet.id), legacy: .legacySnippet(snippet.id))
        }
    }

    static func restore(_ records: [SnippetShortcutBackupRecord]) {
        for name in KeyboardShortcuts.storedNames where dynamicEntity(from: name.rawValue) != nil {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }

        for record in records {
            let name: KeyboardShortcuts.Name
            switch record.entityKind {
            case .folder:
                name = .folder(record.entityID)
            case .snippet:
                name = .snippet(record.entityID)
            }
            KeyboardShortcuts.setShortcut(record.shortcut, for: name)
        }
    }

    private enum DynamicEntity {
        case folder(UUID)
        case snippet(UUID)
    }

    private static func shortcut(
        canonical: KeyboardShortcuts.Name,
        legacy: KeyboardShortcuts.Name
    ) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: canonical)
            ?? KeyboardShortcuts.getShortcut(for: legacy)
    }

    private static func migrate(
        canonical: KeyboardShortcuts.Name,
        legacy: KeyboardShortcuts.Name
    ) {
        if KeyboardShortcuts.getShortcut(for: canonical) == nil,
           let shortcut = KeyboardShortcuts.getShortcut(for: legacy) {
            KeyboardShortcuts.setShortcut(shortcut, for: canonical)
        }
        KeyboardShortcuts.setShortcut(nil, for: legacy)
    }

    private static func clear(
        canonical: KeyboardShortcuts.Name,
        legacy: KeyboardShortcuts.Name
    ) {
        KeyboardShortcuts.setShortcut(nil, for: canonical)
        KeyboardShortcuts.setShortcut(nil, for: legacy)
    }

    private static func dynamicEntity(from rawValue: String) -> DynamicEntity? {
        for prefix in ["folder-", "folder."] where rawValue.hasPrefix(prefix) {
            return UUID(uuidString: String(rawValue.dropFirst(prefix.count))).map(DynamicEntity.folder)
        }
        for prefix in ["snippet-", "snippet."] where rawValue.hasPrefix(prefix) {
            return UUID(uuidString: String(rawValue.dropFirst(prefix.count))).map(DynamicEntity.snippet)
        }
        return nil
    }
}

@MainActor
enum ShortcutValidation {
    static func result(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedName: KeyboardShortcuts.Name
    ) -> KeyboardShortcuts.ValidationResult {
        let conflict = KeyboardShortcuts.storedNames.first { name in
            name.rawValue != excludedName.rawValue
                && KeyboardShortcuts.getShortcut(for: name) == shortcut
        }
        guard let conflict else {
            return .allow
        }

        return .disallow(
            reason: String(
                format: L10n.string("shortcuts.conflict"),
                conflict.rawValue
            )
        )
    }
}

struct SwiftClipShortcutRecorder: View {
    var title: String
    var name: KeyboardShortcuts.Name

    var body: some View {
        KeyboardShortcuts.Recorder(title, name: name)
            .shortcutValidation { shortcut in
                ShortcutValidation.result(for: shortcut, excluding: name)
            }
    }
}
