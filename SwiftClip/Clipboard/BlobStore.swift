import Foundation

struct BlobReference: Codable, Equatable, Sendable {
    var filename: String
    var byteCount: Int
    var pasteboardTypeIdentifier: String
}

actor BlobStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func write(data: Data, fileExtension: String, pasteboardTypeIdentifier: String) throws -> BlobReference {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).\(fileExtension)"
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)

        do {
            try data.write(to: url, options: .atomic)
            return BlobReference(
                filename: filename,
                byteCount: data.count,
                pasteboardTypeIdentifier: pasteboardTypeIdentifier
            )
        } catch {
            throw SwiftClipError.blobWriteFailed(error.localizedDescription)
        }
    }

    func read(filename: String) throws -> Data {
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwiftClipError.blobNotFound(filename)
        }
        return try Data(contentsOf: url)
    }

    func delete(filename: String) {
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            AppLog.history.error("Could not delete blob \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearAll() {
        do {
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                return
            }

            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            AppLog.history.error("Could not clear blobs: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sweep(keeping filenames: Set<String>) {
        do {
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                return
            }

            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            for url in contents where !filenames.contains(url.lastPathComponent) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            AppLog.history.error("Could not sweep blobs: \(error.localizedDescription, privacy: .public)")
        }
    }
}
