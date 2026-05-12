import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteEngine {
    var onPasteboardWrite: (() -> Void)?

    private let preferences: PreferencesStore
    private let blobStore: BlobStore

    init(preferences: PreferencesStore, blobStore: BlobStore) {
        self.preferences = preferences
        self.blobStore = blobStore
    }

    func paste(item: ClipboardItem, asPlainText: Bool = false) {
        Task {
            let didWrite = await write(item: item, asPlainText: asPlainText)
            guard didWrite else {
                return
            }

            if preferences.state.pasteAfterSelection {
                synthesizeCommandV()
            }
        }
    }

    func paste(snippet: SnippetLeaf) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var didWrite = false

        let urls = snippet.attachmentURLs
            .compactMap(URL.init(string:))
            .filter { $0.isFileURL }

        if !urls.isEmpty {
            didWrite = pasteboard.writeObjects(urls as [NSURL])
        }

        if !snippet.content.isEmpty {
            didWrite = pasteboard.setString(snippet.content, forType: .string) || didWrite
        }

        guard didWrite else {
            return
        }

        onPasteboardWrite?()

        if preferences.state.pasteAfterSelection {
            synthesizeCommandV()
        }
    }

    private func write(item: ClipboardItem, asPlainText: Bool) async -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if asPlainText, let text = item.textValue {
            pasteboard.setString(text, forType: .string)
            onPasteboardWrite?()
            return true
        }

        if let text = item.textValue {
            let type = NSPasteboard.PasteboardType(item.pasteboardTypeIdentifier ?? item.kind.fallbackPasteboardType.rawValue)
            pasteboard.setString(text, forType: type)
            if type != .string {
                pasteboard.setString(text, forType: .string)
            }
            onPasteboardWrite?()
            return true
        }

        if !item.fileURLs.isEmpty {
            let urls = item.fileURLs.compactMap(URL.init(string:))
            pasteboard.writeObjects(urls as [NSURL])
            onPasteboardWrite?()
            return true
        }

        guard let blobFilename = item.blobFilename else {
            return false
        }

        do {
            let data = try await blobStore.read(filename: blobFilename)
            let type = NSPasteboard.PasteboardType(item.pasteboardTypeIdentifier ?? item.kind.fallbackPasteboardType.rawValue)
            pasteboard.setData(data, forType: type)
            onPasteboardWrite?()
            return true
        } catch {
            AppLog.clipboard.error("Could not paste history item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func synthesizeCommandV() {
        guard PermissionsProbe.isAccessibilityTrusted(prompt: false) else {
            AppLog.clipboard.info("Accessibility permission is not granted; pasteboard was updated without keystroke injection")
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
