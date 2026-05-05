import Foundation
import SwiftData

@Model
final class SnippetFolder {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortIndex: Int
    var isEnabled: Bool
    var shortcutName: String?
    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder) var snippets: [Snippet]

    init(
        id: UUID = UUID(),
        title: String,
        sortIndex: Int,
        isEnabled: Bool = true,
        shortcutName: String? = nil,
        snippets: [Snippet] = []
    ) {
        self.id = id
        self.title = title
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
        self.shortcutName = shortcutName
        self.snippets = snippets
    }
}

struct SnippetSummary: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var sortIndex: Int
    var isEnabled: Bool
    var snippets: [SnippetLeaf]

    init(
        id: UUID = UUID(),
        title: String,
        sortIndex: Int = 0,
        isEnabled: Bool = true,
        snippets: [SnippetLeaf] = []
    ) {
        self.id = id
        self.title = title
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
        self.snippets = snippets
    }
}
