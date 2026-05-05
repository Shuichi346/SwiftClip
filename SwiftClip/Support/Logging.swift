import OSLog

enum AppLog {
    static let subsystem = "app.swiftclip"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let snippets = Logger(subsystem: subsystem, category: "snippets")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
}
