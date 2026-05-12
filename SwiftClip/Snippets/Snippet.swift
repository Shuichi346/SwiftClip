import Foundation
import SwiftData

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var attachmentURLs: [String]
    var sortIndex: Int
    var isEnabled: Bool
    var shortcutName: String?
    var folder: SnippetFolder?

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        attachmentURLs: [String] = [],
        sortIndex: Int,
        isEnabled: Bool = true,
        shortcutName: String? = nil,
        folder: SnippetFolder? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.attachmentURLs = attachmentURLs
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
    var attachmentURLs: [String]
    var sortIndex: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        attachmentURLs: [String] = [],
        sortIndex: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.attachmentURLs = attachmentURLs
        self.sortIndex = sortIndex
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case attachmentURLs
        case sortIndex
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        attachmentURLs = try container.decodeIfPresent([String].self, forKey: .attachmentURLs) ?? []
        sortIndex = try container.decode(Int.self, forKey: .sortIndex)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
}
