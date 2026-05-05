import Foundation

enum SwiftClipError: Error, LocalizedError, Equatable {
    case appSupportUnavailable
    case oversizedPayload(limit: Int)
    case blobNotFound(String)
    case blobWriteFailed(String)
    case historyPersistenceFailed(String)
    case preferencesPersistenceFailed(String)
    case snippetsPersistenceFailed(String)
    case xmlParseFailed(String)
    case xmlEncodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .appSupportUnavailable:
            return L10n.string("error.appSupportUnavailable")
        case .oversizedPayload(let limit):
            return String(format: L10n.string("error.oversizedPayload"), limit)
        case .blobNotFound(let filename):
            return String(format: L10n.string("error.blobNotFound"), filename)
        case .blobWriteFailed(let message):
            return message
        case .historyPersistenceFailed(let message):
            return message
        case .preferencesPersistenceFailed(let message):
            return message
        case .snippetsPersistenceFailed(let message):
            return message
        case .xmlParseFailed(let message):
            return message
        case .xmlEncodeFailed(let message):
            return message
        }
    }
}
