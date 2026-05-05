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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
