import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: ClipboardItemKind
    var createdAt: Date
    var title: String
    var textValue: String?
    var fileURLs: [String]
    var blobFilename: String?
    var byteCount: Int
    var pasteboardTypeIdentifier: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        createdAt: Date = Date(),
        title: String,
        textValue: String? = nil,
        fileURLs: [String] = [],
        blobFilename: String? = nil,
        byteCount: Int,
        pasteboardTypeIdentifier: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.title = title
        self.textValue = textValue
        self.fileURLs = fileURLs
        self.blobFilename = blobFilename
        self.byteCount = byteCount
        self.pasteboardTypeIdentifier = pasteboardTypeIdentifier
    }

    func menuTitle(index: Int, preferences: PreferencesState) -> String {
        let limit = preferences.menuTitleCharacterLimit
        let text = title.replacingOccurrences(of: "\n", with: " ").swiftClipTruncated(to: limit)

        guard preferences.showNumbers else {
            return text
        }

        let displayedIndex = preferences.startNumbersAtZero ? index : index + 1
        return "\(displayedIndex). \(text)"
    }
}

struct ClipboardCapture: Sendable {
    var kind: ClipboardItemKind
    var title: String
    var textValue: String?
    var fileURLs: [String]
    var data: Data?
    var byteCount: Int
    var pasteboardTypeIdentifier: String?
}
