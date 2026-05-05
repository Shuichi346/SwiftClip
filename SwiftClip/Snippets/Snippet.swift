import Foundation
import SwiftData

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var sortIndex: Int
    var isEnabled: Bool
    var shortcutName: String?
    var folder: SnippetFolder?

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        sortIndex: Int,
        isEnabled: Bool = true,
        shortcutName: String? = nil,
        folder: SnippetFolder? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
        self.shortcutName = shortcutName
        self.folder = folder
    }
}

struct SnippetLeaf: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var sortIndex: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        sortIndex: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
    }
}
