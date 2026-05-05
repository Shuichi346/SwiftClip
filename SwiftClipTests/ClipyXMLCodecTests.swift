import XCTest
@testable import SwiftClip

final class ClipyXMLCodecTests: XCTestCase {
    func testDecodeSampleClipyXML() throws {
        let data = try sampleData()
        let folders = try ClipyXMLCodec.decode(data: data)

        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(folders[0].title, "NotebookLM")
        XCTAssertEqual(folders[0].snippets.count, 2)
        XCTAssertEqual(folders[0].snippets[0].content, "Summarize this source.\nKeep the answer concise.")
        XCTAssertEqual(folders[1].title, "使い方色々")
        XCTAssertEqual(folders[1].snippets.count, 1)
    }

    func testEncodeMatchesSampleAfterDecode() throws {
        let data = try sampleData()
        let folders = try ClipyXMLCodec.decode(data: data)
        let encoded = try ClipyXMLCodec.encode(folders: folders)

        XCTAssertEqual(
            String(data: encoded, encoding: .utf8),
            String(data: data, encoding: .utf8)
        )
    }

    private func sampleData() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "sample-clipy", withExtension: "xml"))
        return try Data(contentsOf: url)
    }
}
