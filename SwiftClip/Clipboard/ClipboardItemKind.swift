import AppKit
import Foundation

enum ClipboardItemKind: String, Codable, CaseIterable, Sendable {
    case plainText
    case richText
    case rtfd
    case fileURL
    case url
    case image
    case pdf

    var defaultFileExtension: String {
        switch self {
        case .plainText:
            return "txt"
        case .richText:
            return "rtf"
        case .rtfd:
            return "rtfd"
        case .fileURL:
            return "url"
        case .url:
            return "url"
        case .image:
            return "tiff"
        case .pdf:
            return "pdf"
        }
    }

    var fallbackPasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .plainText:
            return .string
        case .richText:
            return .rtf
        case .rtfd:
            return .rtfd
        case .fileURL:
            return .fileURL
        case .url:
            return .URL
        case .image:
            return .tiff
        case .pdf:
            return .pdf
        }
    }
}
