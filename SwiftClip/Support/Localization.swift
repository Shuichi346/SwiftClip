import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
