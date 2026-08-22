import AppKit
import XCTest
@testable import SwiftClip

@MainActor
final class PasteboardCaptureTests: XCTestCase {
    func testRTFDAndRTFTakePriorityOverURLAndPlainText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/plain", forType: .string)
        pasteboard.setString("https://example.com/url", forType: .URL)
        pasteboard.setData(Data("rtf".utf8), forType: .rtf)
        pasteboard.setData(Data("rtfd".utf8), forType: .rtfd)

        var preferences = PreferencesState()
        let rtfdCapture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: preferences)
        )
        XCTAssertEqual(rtfdCapture.kind, .rtfd)
        XCTAssertEqual(rtfdCapture.data, Data("rtfd".utf8))

        preferences.formatRTFD = false
        let rtfCapture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: preferences)
        )
        XCTAssertEqual(rtfCapture.kind, .richText)
        XCTAssertEqual(rtfCapture.data, Data("rtf".utf8))
    }

    func testLargeTextUsesBoundedPreviewAndBlobPayload() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let text = String(repeating: "x", count: ClipboardCapture.inlineTextByteLimit + 1)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .plainText)
        XCTAssertEqual(capture.title.count, ClipboardCapture.titlePreviewLimit)
        XCTAssertNil(capture.textValue)
        XCTAssertEqual(capture.data, Data(text.utf8))
    }

    func testSelfWriteFilterSuppressesOnlyTheRecordedChange() {
        var filter = PasteboardChangeFilter()
        filter.recordSelfWrite(changeCount: 10)

        XCTAssertFalse(filter.shouldSuppress(observedChangeCount: 11))

        filter.recordSelfWrite(changeCount: 12)
        XCTAssertTrue(filter.shouldSuppress(observedChangeCount: 12))
        XCTAssertFalse(filter.shouldSuppress(observedChangeCount: 13))
    }
}
