import XCTest
@testable import SwiftClip

final class JSONPersistenceQueueTests: XCTestCase {
    private struct Payload: Codable, Equatable, Sendable {
        let value: Int
    }

    func testWritesSnapshotsInEnqueueOrder() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let queue = JSONPersistenceQueue(label: "app.swiftclip.tests.persistence")

        for value in 0..<100 {
            queue.write(Payload(value: value), to: url) { error in
                XCTFail("Unexpected persistence error: \(error)")
            }
        }
        queue.flush()

        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        XCTAssertEqual(payload.value, 99)
    }
}
