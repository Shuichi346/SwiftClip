import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteEngine {
    var onPasteboardWrite: ((Int) -> Void)?

    private let preferences: PreferencesStore
    private let blobStore: any BlobStoring

    init(preferences: PreferencesStore, blobStore: any BlobStoring) {
        self.preferences = preferences
        self.blobStore = blobStore
    }

    func paste(item: ClipboardItem) {
        Task {
            let didWrite = await write(
                item: item,
                asPlainText: preferences.state.alwaysPasteAsPlainText
            )
            guard didWrite else {
                return
            }

            if preferences.state.pasteAfterSelection {
                synthesizeCommandV()
            }
        }
    }

    func paste(snippet: SnippetLeaf) {
        if preferences.state.alwaysPasteAsPlainText {
            guard writePasteboardObjects(pasteboardTextObjects(for: snippet)) else {
                return
            }

            if preferences.state.pasteAfterSelection {
                synthesizeCommandV()
            }
            return
        }

        let targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if preferences.state.pasteAfterSelection,
           PermissionsProbe.isAccessibilityTrusted(prompt: false),
           shouldUseTwoStepMixedSnippetPaste(for: snippet, targetBundleID: targetBundleID) {
            pasteSnippetTextThenAttachments(snippet)
            return
        }

        let objects = pasteboardObjects(for: snippet)
        guard !objects.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects(objects)

        guard didWrite else {
            return
        }

        onPasteboardWrite?(pasteboard.changeCount)

        if preferences.state.pasteAfterSelection {
            synthesizeCommandV()
        }
    }

    private func write(item: ClipboardItem, asPlainText: Bool) async -> Bool {
        if asPlainText {
            guard let text = await plainText(for: item) else {
                return false
            }
            return writeText(text, forType: .string)
        }

        if !item.fileURLs.isEmpty {
            let urls = item.fileURLs
                .compactMap(URL.init(string:))
                .filter { url in
                    url.isFileURL && FileManager.default.fileExists(atPath: url.path)
                }
            guard !urls.isEmpty else {
                return false
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return completePasteboardWrite(pasteboard.writeObjects(urls as [NSURL]))
        }

        if let blobFilename = item.blobFilename {
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

        if let text = item.textValue {
            let type = NSPasteboard.PasteboardType(item.pasteboardTypeIdentifier ?? item.kind.fallbackPasteboardType.rawValue)
            return writeText(text, forType: type)
        }

        return false
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
            onPasteboardWrite?(NSPasteboard.general.changeCount)
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
            .filter { url in
                url.isFileURL && FileManager.default.fileExists(atPath: url.path)
            }
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
            onPasteboardWrite?(pasteboard.changeCount)
        }

        return didWrite
    }

    private func shouldUseTwoStepMixedSnippetPaste(for snippet: SnippetLeaf, targetBundleID: String?) -> Bool {
        !snippet.content.isEmpty
            && !pasteboardAttachmentObjects(for: snippet).isEmpty
            && preferences.shouldUseTwoStepMixedSnippetPaste(bundleID: targetBundleID)
    }

    private func plainText(for item: ClipboardItem) async -> String? {
        if let textValue = item.textValue {
            return textValue
        }

        if !item.fileURLs.isEmpty {
            let values = item.fileURLs.compactMap { value -> String? in
                guard let url = URL(string: value), url.isFileURL else {
                    return nil
                }
                return url.path(percentEncoded: false)
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        }

        guard let blobFilename = item.blobFilename else {
            return nil
        }

        do {
            let data = try await blobStore.read(filename: blobFilename)
            switch item.kind {
            case .plainText, .url:
                return String(data: data, encoding: .utf8)
            case .richText:
                return try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ).string
            case .rtfd:
                return try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtfd],
                    documentAttributes: nil
                ).string
            case .html:
                return try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.html],
                    documentAttributes: nil
                ).string
            case .fileURL, .image, .pdf:
                return nil
            }
        } catch {
            AppLog.clipboard.error("Could not convert history item to plain text: \(error.localizedDescription, privacy: .public)")
            return nil
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
