import Foundation
import KeyboardShortcuts

struct SnippetShortcutBackupRecord: Codable, Equatable, Sendable {
    enum EntityKind: String, Codable, Sendable {
        case folder
        case snippet
    }

    var entityKind: EntityKind
    var entityID: UUID
    var shortcut: KeyboardShortcuts.Shortcut
}

struct SnippetLibraryBackupManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Attachment: Codable, Equatable, Sendable {
        var originalURL: String
        var archivedFilename: String
    }

    var version: Int
    var createdAt: Date
    var folders: [SnippetSummary]
    var shortcuts: [SnippetShortcutBackupRecord]
    var attachments: [Attachment]
}

struct PreparedSnippetLibraryRestore: Sendable {
    var folders: [SnippetSummary]
    var shortcuts: [SnippetShortcutBackupRecord]
    var copiedAttachmentURLs: [String]
}

actor SnippetLibraryBackupStore {
    static let fileExtension = "swiftclipbackup"

    private let backupDirectoryURL: URL
    private let attachmentDirectoryURL: URL

    init(backupDirectoryURL: URL, attachmentDirectoryURL: URL) {
        self.backupDirectoryURL = backupDirectoryURL.standardizedFileURL
        self.attachmentDirectoryURL = attachmentDirectoryURL.standardizedFileURL
    }

    func createBackup(
        folders: [SnippetSummary],
        shortcuts: [SnippetShortcutBackupRecord]
    ) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        let temporaryURL = backupDirectoryURL.appendingPathComponent(
            ".backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let attachmentsURL = temporaryURL.appendingPathComponent("Attachments", isDirectory: true)

        do {
            try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            var attachmentRecords: [SnippetLibraryBackupManifest.Attachment] = []

            let attachmentURLs = Set(folders.flatMap { folder in
                folder.snippets.flatMap(\.attachmentURLs)
            })

            for attachmentURL in attachmentURLs.sorted() {
                guard let sourceURL = URL(string: attachmentURL),
                      sourceURL.isFileURL,
                      isManagedFileURL(sourceURL) else {
                    continue
                }
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw SwiftClipError.snippetBackupFailed(
                        "Managed attachment is missing: \(sourceURL.lastPathComponent)"
                    )
                }

                let archivedFilename = UUID().uuidString
                let destinationURL = attachmentsURL.appendingPathComponent(archivedFilename)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                attachmentRecords.append(
                    .init(originalURL: attachmentURL, archivedFilename: archivedFilename)
                )
            }

            let manifest = SnippetLibraryBackupManifest(
                version: SnippetLibraryBackupManifest.currentVersion,
                createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
                folders: folders,
                shortcuts: shortcuts,
                attachments: attachmentRecords
            )
            let manifestURL = temporaryURL.appendingPathComponent("manifest.json", isDirectory: false)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

            let validated = try readManifest(from: temporaryURL)
            guard validated == manifest else {
                throw SwiftClipError.invalidSnippetBackup("Backup validation failed.")
            }
            try validateManifest(validated)

            let stamp = ISO8601DateFormatter()
                .string(from: manifest.createdAt)
                .replacingOccurrences(of: ":", with: "-")
            let destinationURL = backupDirectoryURL.appendingPathComponent(
                "snippets-\(stamp)-\(UUID().uuidString.prefix(8)).\(Self.fileExtension)",
                isDirectory: true
            )
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if let error = error as? SwiftClipError {
                throw error
            }
            throw SwiftClipError.snippetBackupFailed(error.localizedDescription)
        }
    }

    func prepareRestore(from backupURL: URL) throws -> PreparedSnippetLibraryRestore {
        let fileManager = FileManager.default
        let manifest = try readManifest(from: backupURL)
        try validateManifest(manifest)

        try fileManager.createDirectory(at: attachmentDirectoryURL, withIntermediateDirectories: true)
        var copiedURLs: [URL] = []
        var restoredURLByOriginal: [String: String] = [:]

        do {
            for record in manifest.attachments {
                guard isSinglePathComponent(record.archivedFilename),
                      let originalURL = URL(string: record.originalURL),
                      originalURL.isFileURL,
                      !originalURL.lastPathComponent.isEmpty else {
                    throw SwiftClipError.invalidSnippetBackup("Backup contains an invalid attachment record.")
                }

                let sourceURL = backupURL
                    .appendingPathComponent("Attachments", isDirectory: true)
                    .appendingPathComponent(record.archivedFilename, isDirectory: false)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw SwiftClipError.invalidSnippetBackup(
                        "Backup attachment is missing: \(record.archivedFilename)"
                    )
                }

                let preferredURL = attachmentDirectoryURL.appendingPathComponent(
                    originalURL.lastPathComponent,
                    isDirectory: false
                )
                let destinationURL: URL
                if fileManager.fileExists(atPath: preferredURL.path) {
                    destinationURL = attachmentDirectoryURL.appendingPathComponent(
                        "\(UUID().uuidString)-\(preferredURL.lastPathComponent)",
                        isDirectory: false
                    )
                } else {
                    destinationURL = preferredURL
                }

                guard isManagedFileURL(destinationURL) else {
                    throw SwiftClipError.invalidSnippetBackup("Backup attachment destination is invalid.")
                }

                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                copiedURLs.append(destinationURL)
                restoredURLByOriginal[record.originalURL] = destinationURL.absoluteString
            }

            let restoredFolders = manifest.folders.map { folder in
                var folder = folder
                folder.snippets = folder.snippets.map { snippet in
                    var snippet = snippet
                    snippet.attachmentURLs = snippet.attachmentURLs.map {
                        restoredURLByOriginal[$0] ?? $0
                    }
                    return snippet
                }
                return folder
            }

            return PreparedSnippetLibraryRestore(
                folders: restoredFolders,
                shortcuts: manifest.shortcuts,
                copiedAttachmentURLs: copiedURLs.map(\.absoluteString)
            )
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            if let error = error as? SwiftClipError {
                throw error
            }
            throw SwiftClipError.invalidSnippetBackup(error.localizedDescription)
        }
    }

    func discardPreparedRestore(_ restore: PreparedSnippetLibraryRestore) {
        for attachmentURL in restore.copiedAttachmentURLs {
            guard let url = URL(string: attachmentURL),
                  url.isFileURL,
                  isManagedFileURL(url) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func readManifest(from backupURL: URL) throws -> SnippetLibraryBackupManifest {
        let manifestURL = backupURL.appendingPathComponent("manifest.json", isDirectory: false)
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SnippetLibraryBackupManifest.self, from: data)
        } catch {
            throw SwiftClipError.invalidSnippetBackup(error.localizedDescription)
        }
    }

    private func validateManifest(_ manifest: SnippetLibraryBackupManifest) throws {
        guard manifest.version == SnippetLibraryBackupManifest.currentVersion else {
            throw SwiftClipError.invalidSnippetBackup(
                "Unsupported backup version: \(manifest.version)"
            )
        }

        let folderIDs = manifest.folders.map(\.id)
        guard Set(folderIDs).count == folderIDs.count else {
            throw SwiftClipError.invalidSnippetBackup("Backup contains duplicate folder IDs.")
        }

        let snippets = manifest.folders.flatMap(\.snippets)
        let snippetIDs = snippets.map(\.id)
        guard Set(snippetIDs).count == snippetIDs.count else {
            throw SwiftClipError.invalidSnippetBackup("Backup contains duplicate snippet IDs.")
        }

        let referencedAttachmentURLs = Set(snippets.flatMap(\.attachmentURLs))
        let attachmentOriginalURLs = manifest.attachments.map(\.originalURL)
        let archivedFilenames = manifest.attachments.map(\.archivedFilename)
        guard Set(attachmentOriginalURLs).count == attachmentOriginalURLs.count,
              Set(archivedFilenames).count == archivedFilenames.count,
              Set(attachmentOriginalURLs).isSubset(of: referencedAttachmentURLs),
              manifest.attachments.allSatisfy({ record in
                  isSinglePathComponent(record.archivedFilename)
                      && URL(string: record.originalURL)?.isFileURL == true
              }) else {
            throw SwiftClipError.invalidSnippetBackup("Backup contains invalid attachment metadata.")
        }

        var shortcutEntities: Set<String> = []
        var shortcutValues: Set<KeyboardShortcuts.Shortcut> = []
        let folderIDSet = Set(folderIDs)
        let snippetIDSet = Set(snippetIDs)
        for record in manifest.shortcuts {
            let entityKey = "\(record.entityKind.rawValue):\(record.entityID.uuidString)"
            let entityExists: Bool
            switch record.entityKind {
            case .folder:
                entityExists = folderIDSet.contains(record.entityID)
            case .snippet:
                entityExists = snippetIDSet.contains(record.entityID)
            }

            guard entityExists,
                  shortcutEntities.insert(entityKey).inserted,
                  shortcutValues.insert(record.shortcut).inserted else {
                throw SwiftClipError.invalidSnippetBackup("Backup contains invalid shortcut metadata.")
            }
        }
    }

    private func isManagedFileURL(_ url: URL) -> Bool {
        let attachmentPath = url.standardizedFileURL.path
        let directoryPath = attachmentDirectoryURL.path
        return attachmentPath != directoryPath
            && attachmentPath.hasPrefix(directoryPath + "/")
    }

    private func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("\0")
    }
}
