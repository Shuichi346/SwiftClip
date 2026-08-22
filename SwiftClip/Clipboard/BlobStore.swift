import Foundation

struct BlobReference: Codable, Equatable, Sendable {
    var filename: String
    var byteCount: Int
    var pasteboardTypeIdentifier: String
}

protocol BlobStoring: Sendable {
    func write(data: Data, fileExtension: String, pasteboardTypeIdentifier: String) async throws -> BlobReference
    func read(filename: String) async throws -> Data
    func delete(filename: String) async
    func clearAll() async
    func sweep(keeping filenames: Set<String>) async
}

actor BlobStore: BlobStoring {
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
        let url = try validatedFileURL(filename: filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwiftClipError.blobNotFound(filename)
        }

        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw SwiftClipError.invalidBlobFilename(filename)
        }
        return try Data(contentsOf: url)
    }

    func delete(filename: String) {
        do {
            let url = try validatedFileURL(filename: filename)
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

    private func validatedFileURL(filename: String) throws -> URL {
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              !filename.contains("/"),
              !filename.contains("\\"),
              !filename.contains("\0") else {
            throw SwiftClipError.invalidBlobFilename(filename)
        }

        let filenameURL = URL(fileURLWithPath: filename, isDirectory: false)
        let stem = filenameURL.deletingPathExtension().lastPathComponent
        let fileExtension = filenameURL.pathExtension
        guard filenameURL.lastPathComponent == filename,
              UUID(uuidString: stem) != nil,
              !fileExtension.isEmpty else {
            throw SwiftClipError.invalidBlobFilename(filename)
        }

        let url = directoryURL.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
        guard parentURL == directoryURL.standardizedFileURL else {
            throw SwiftClipError.invalidBlobFilename(filename)
        }
        return url
    }
}
