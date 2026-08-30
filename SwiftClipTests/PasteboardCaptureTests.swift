import AppKit
import XCTest
@testable import SwiftClip

@MainActor
final class PasteboardCaptureTests: XCTestCase {
    func testRTFDAndRTFTakePriorityOverURLAndPlainText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let rtfData = try richTextData("RTF preview", documentType: .rtf)
        let rtfdData = try richTextData("RTFD preview", documentType: .rtfd)
        pasteboard.clearContents()
        pasteboard.setString("Readable clipboard text", forType: .string)
        pasteboard.setString("https://example.com/url", forType: .URL)
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setData(rtfdData, forType: .rtfd)

        var preferences = PreferencesState()
        let rtfdCapture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: preferences)
        )
        XCTAssertEqual(rtfdCapture.kind, .rtfd)
        XCTAssertEqual(rtfdCapture.title, "Readable clipboard text")
        XCTAssertEqual(rtfdCapture.data, rtfdData)
        XCTAssertNil(rtfdCapture.textValue)

        preferences.formatRTFD = false
        let rtfCapture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: preferences)
        )
        XCTAssertEqual(rtfCapture.kind, .richText)
        XCTAssertEqual(rtfCapture.title, "Readable clipboard text")
        XCTAssertEqual(rtfCapture.data, rtfData)
        XCTAssertNil(rtfCapture.textValue)
    }

    func testHTMLTakesPriorityOverURLAndPlainText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let htmlData = Data("<html><body><strong>Styled</strong> text</body></html>".utf8)
        pasteboard.clearContents()
        pasteboard.setString("Styled text", forType: .string)
        pasteboard.setString("https://example.com/url", forType: .URL)
        pasteboard.setData(htmlData, forType: .html)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .html)
        XCTAssertEqual(capture.title, "Styled text")
        XCTAssertEqual(capture.data, htmlData)
        XCTAssertNil(capture.textValue)
        XCTAssertEqual(capture.pasteboardTypeIdentifier, NSPasteboard.PasteboardType.html.rawValue)
    }

    func testRichTextTitleFallsBackToDecodedRTFText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let rtfData = try richTextData("Decoded styled text", documentType: .rtf)
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .richText)
        XCTAssertEqual(capture.title, "Decoded styled text")
        XCTAssertEqual(capture.data, rtfData)
    }

    func testRichTextTitleFallsBackToDecodedRTFDText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let rtfdData = try richTextData("Decoded RTFD text", documentType: .rtfd)
        pasteboard.clearContents()
        pasteboard.setData(rtfdData, forType: .rtfd)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .rtfd)
        XCTAssertEqual(capture.title, "Decoded RTFD text")
        XCTAssertEqual(capture.data, rtfdData)
    }

    func testRichTextTitleFallsBackToDecodedHTMLText() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        let htmlData = Data("<html><body><strong>Decoded</strong> HTML text</body></html>".utf8)
        pasteboard.clearContents()
        pasteboard.setData(htmlData, forType: .html)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .html)
        XCTAssertEqual(capture.title, "Decoded HTML text")
        XCTAssertEqual(capture.data, htmlData)
    }

    func testInvalidRichTextUsesGenericFallbackTitle() throws {
        let pasteboard = NSPasteboard(name: .init("app.swiftclip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data("invalid rtf".utf8), forType: .rtf)

        let capture = try XCTUnwrap(
            ClipboardCapture.make(from: pasteboard, preferences: PreferencesState())
        )

        XCTAssertEqual(capture.kind, .richText)
        XCTAssertEqual(capture.title, L10n.string("history.richText"))
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

    private func richTextData(
        _ string: String,
        documentType: NSAttributedString.DocumentType
    ) throws -> Data {
        let attributedString = NSAttributedString(string: string)
        return try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: documentType]
        )
    }
}
