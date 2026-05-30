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
        let targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if preferences.state.pasteAfterSelection,
           PermissionsProbe.isAccessibilityTrusted(prompt: false),
           shouldUseTwoStepMixedSnippetPaste(for: snippet, targetBundleID: targetBundleID) {
            pasteSnippetTextThenAttachments(snippet)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let objects = pasteboardObjects(for: snippet)
        let didWrite = !objects.isEmpty && pasteboard.writeObjects(objects)

        guard didWrite else {
            return
        }

        onPasteboardWrite?()

        if preferences.state.pasteAfterSelection {
            synthesizeCommandV()
        }
    }

    private func write(item: ClipboardItem, asPlainText: Bool) async -> Bool {
        if asPlainText, let text = item.textValue {
            return writeText(text, forType: .string)
        }

        if let text = item.textValue {
            let type = NSPasteboard.PasteboardType(item.pasteboardTypeIdentifier ?? item.kind.fallbackPasteboardType.rawValue)
            return writeText(text, forType: type)
        }

        if !item.fileURLs.isEmpty {
            let urls = item.fileURLs
                .compactMap(URL.init(string:))
                .filter(\.isFileURL)
            guard !urls.isEmpty else {
                return false
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return completePasteboardWrite(pasteboard.writeObjects(urls as [NSURL]))
        }

        guard let blobFilename = item.blobFilename else {
            return false
        }

        do {
            let data = try await blobStore.read(filename: blobFilename)
            let type = NSPasteboard.PasteboardType(item.pasteboardTypeIdentifier ?? item.kind.fallbackPasteboardType.rawValue)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return completePasteboardWrite(pasteboard.setData(data, forType: type))
        } catch {
            AppLog.clipboard.error("Could not paste history item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func writeText(_ text: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if type == .string {
            return completePasteboardWrite(pasteboard.setString(text, forType: .string))
        } else {
            let wrotePrimaryType = pasteboard.setString(text, forType: type)
            let wrotePlainText = pasteboard.setString(text, forType: .string)
            return completePasteboardWrite(wrotePrimaryType || wrotePlainText)
        }
    }

    private func completePasteboardWrite(_ didWrite: Bool) -> Bool {
        if didWrite {
            onPasteboardWrite?()
        }
        return didWrite
    }

    private func pasteboardObjects(for snippet: SnippetLeaf) -> [NSPasteboardWriting] {
        pasteboardTextObjects(for: snippet) + pasteboardAttachmentObjects(for: snippet)
    }

    private func pasteboardTextObjects(for snippet: SnippetLeaf) -> [NSPasteboardWriting] {
        guard !snippet.content.isEmpty else {
            return []
        }

        let textItem = NSPasteboardItem()
        textItem.setString(snippet.content, forType: .string)
        return [textItem]
    }

    private func pasteboardAttachmentObjects(for snippet: SnippetLeaf) -> [NSPasteboardWriting] {
        let urls = snippet.attachmentURLs
            .compactMap(URL.init(string:))
            .filter { $0.isFileURL }
        return urls.map { $0 as NSURL }
    }

    private func pasteSnippetTextThenAttachments(_ snippet: SnippetLeaf) {
        guard writePasteboardObjects(pasteboardTextObjects(for: snippet)) else {
            return
        }

        synthesizeCommandV()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))

            guard writePasteboardObjects(pasteboardAttachmentObjects(for: snippet)) else {
                return
            }

            synthesizeCommandV()
        }
    }

    private func writePasteboardObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        guard !objects.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects(objects)

        if didWrite {
            onPasteboardWrite?()
        }

        return didWrite
    }

    private func shouldUseTwoStepMixedSnippetPaste(for snippet: SnippetLeaf, targetBundleID: String?) -> Bool {
        !snippet.content.isEmpty
            && !pasteboardAttachmentObjects(for: snippet).isEmpty
            && preferences.shouldUseTwoStepMixedSnippetPaste(bundleID: targetBundleID)
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
