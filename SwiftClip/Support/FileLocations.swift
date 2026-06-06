import Foundation

enum FileLocations {
    static let appName = "SwiftClip"

    static let appSupportRoot: URL = {
        let fileManager = FileManager.default
        if let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return supportURL.appendingPathComponent(appName, isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }()

    static var libraryStoreURL: URL {
        appSupportRoot.appendingPathComponent("Library.store", isDirectory: false)
    }

    static var historyIndexURL: URL {
        appSupportRoot.appendingPathComponent("History.json", isDirectory: false)
    }

    static var snippetsIndexURL: URL {
        appSupportRoot.appendingPathComponent("Snippets.json", isDirectory: false)
    }

    static var preferencesURL: URL {
        appSupportRoot.appendingPathComponent("Preferences.json", isDirectory: false)
    }

    static var blobDirectoryURL: URL {
        appSupportRoot.appendingPathComponent("Blobs", isDirectory: true)
    }

    static var snippetAttachmentDirectoryURL: URL {
        appSupportRoot.appendingPathComponent("SnippetAttachments", isDirectory: true)
    }

    static var backupDirectoryURL: URL {
        appSupportRoot.appendingPathComponent("Backups", isDirectory: true)
    }

    static func ensureBaseDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: blobDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snippetAttachmentDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
    }
}
