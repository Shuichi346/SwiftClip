import Foundation

struct SnippetAttachmentFileInfo: Equatable {
    let url: URL
    let byteCount: Int64
}

final class SnippetAttachmentStore {
    static let largeFileWarningThresholdBytes: Int64 = 50 * 1024 * 1024

    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    func copyFiles(_ urls: [URL]) throws -> [URL] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var copiedURLs: [URL] = []
        do {
            for url in urls where url.isFileURL {
                let copiedURL = try copyFile(url)
                copiedURLs.append(copiedURL)
            }
            return copiedURLs
        } catch {
            copiedURLs.forEach { deleteIfManaged($0.absoluteString) }
            throw error
        }
    }

    func deleteIfManaged(_ attachmentURL: String) {
        guard let url = URL(string: attachmentURL),
              url.isFileURL,
              isManagedFileURL(url) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            AppLog.snippets.error("Could not delete snippet attachment \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func isManagedFileURL(_ url: URL) -> Bool {
        let attachmentPath = url.standardizedFileURL.path
        let directoryPath = directoryURL.standardizedFileURL.path
        return attachmentPath == directoryPath || attachmentPath.hasPrefix(directoryPath + "/")
    }

    static func largeFiles(in urls: [URL]) -> [SnippetAttachmentFileInfo] {
        urls.compactMap { url in
            guard let byteCount = fileByteCount(url), byteCount >= largeFileWarningThresholdBytes else {
                return nil
            }
            return SnippetAttachmentFileInfo(url: url, byteCount: byteCount)
        }
    }

    private func copyFile(_ sourceURL: URL) throws -> URL {
        let sourceURL = sourceURL.standardizedFileURL
        if isManagedFileURL(sourceURL) {
            return sourceURL
        }

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = directoryURL.appendingPathComponent(
            "\(UUID().uuidString)-\(sourceURL.lastPathComponent.nonEmptyFileName)",
            isDirectory: false
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func fileByteCount(_ url: URL) -> Int64? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileSizeKey]),
              values.isRegularFile == true else {
            return nil
        }

        if let totalFileSize = values.totalFileSize {
            return Int64(totalFileSize)
        }
        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }
        return nil
    }
}

private extension String {
    var nonEmptyFileName: String {
        isEmpty ? "Attachment" : self
    }
}
