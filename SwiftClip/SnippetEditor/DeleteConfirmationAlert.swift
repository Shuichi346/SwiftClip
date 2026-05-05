import AppKit

enum DeleteConfirmationAlert {
    enum DeleteKind {
        case folder
        case snippet
    }

    @MainActor
    static func confirm(kind: DeleteKind) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert.delete.title")
        alert.informativeText = kind == .folder
            ? L10n.string("alert.delete.folderBody")
            : L10n.string("alert.delete.body")
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.applicationIconName)
        alert.addButton(withTitle: L10n.string("alert.delete.confirm"))
        alert.addButton(withTitle: L10n.string("alert.delete.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
