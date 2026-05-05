import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let mainMenu = Self("mainMenu")
    static let clearHistory = Self("clearHistory")
    static let snippetEditor = Self("snippetEditor")
    static let preferences = Self("preferences")
    static let plainTextPaste = Self("plainTextPaste")
    static let deleteOnSelect = Self("deleteOnSelect")
    static let deleteAfterPaste = Self("deleteAfterPaste")

    static func snippet(_ id: UUID) -> Self {
        Self("snippet.\(id.uuidString)")
    }

    static func folder(_ id: UUID) -> Self {
        Self("folder.\(id.uuidString)")
    }
}
