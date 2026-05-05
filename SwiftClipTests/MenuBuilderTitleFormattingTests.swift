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
}
