import XCTest
@testable import SwiftClip

final class BlobStoreTests: XCTestCase {
    func testWriteReadAndSweepBlob() async throws {
        let directory = try temporaryDirectory()
        let store = BlobStore(directoryURL: directory)
        let data = Data("hello".utf8)

        let reference = try await store.write(
            data: data,
            fileExtension: "txt",
            pasteboardTypeIdentifier: "public.utf8-plain-text"
        )

        let readData = try await store.read(filename: reference.filename)
        XCTAssertEqual(readData, data)

        await store.sweep(keeping: [])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testReadRejectsPathTraversal() async throws {
        let store = BlobStore(directoryURL: try temporaryDirectory())

        do {
            _ = try await store.read(filename: "../History.json")
            XCTFail("Expected traversal filename to be rejected")
        } catch {
            XCTAssertEqual(error as? SwiftClipError, .invalidBlobFilename("../History.json"))
        }
    }

    func testReadRejectsSymbolicLinks() async throws {
        let directory = try temporaryDirectory()
        let targetURL = directory.appendingPathComponent("target.txt", isDirectory: false)
        try Data("secret".utf8).write(to: targetURL, options: .atomic)
        let filename = "C9B46EC3-E568-4377-8752-7FF1B85635BC.txt"
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(filename, isDirectory: false),
            withDestinationURL: targetURL
        )
        let store = BlobStore(directoryURL: directory)

        do {
            _ = try await store.read(filename: filename)
            XCTFail("Expected symbolic link to be rejected")
        } catch {
            XCTAssertEqual(error as? SwiftClipError, .invalidBlobFilename(filename))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
