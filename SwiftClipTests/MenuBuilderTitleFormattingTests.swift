import XCTest
@testable import SwiftClip

final class MenuBuilderTitleFormattingTests: XCTestCase {
    func testNumberedMenuTitleTruncates() {
        var preferences = PreferencesState()
        preferences.menuTitleCharacterLimit = 8
        preferences.showNumbers = true
        preferences.startNumbersAtZero = false

        let item = ClipboardItem(kind: .plainText, title: "abcdefghijklmnopqrstuvwxyz", byteCount: 26)

        XCTAssertEqual(item.menuTitle(index: 0, preferences: preferences), "1. abcde...")
    }

    func testZeroBasedNumbering() {
        var preferences = PreferencesState()
        preferences.showNumbers = true
        preferences.startNumbersAtZero = true

        let item = ClipboardItem(kind: .plainText, title: "Hello", byteCount: 5)

        XCTAssertEqual(item.menuTitle(index: 0, preferences: preferences), "0. Hello")
    }

    func testSnippetTooltipBoundsContentAndAttachmentNames() throws {
        let attachmentURLs = (0..<10).map { index in
            URL(
                fileURLWithPath: "/tmp/\(index)-\(String(repeating: "attachment", count: 20)).txt"
            ).absoluteString
        }
        let snippet = SnippetLeaf(
            title: "Large",
            content: String(repeating: "content", count: 100),
            attachmentURLs: attachmentURLs
        )

        let tooltip = try XCTUnwrap(SnippetsMenuSection.tooltip(for: snippet))
        let lines = tooltip.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines.first?.count, 240)
        XCTAssertTrue(tooltip.contains("+5"))
        XCTAssertLessThan(tooltip.count, 600)
    }
}
