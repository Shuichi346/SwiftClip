import AppKit
import Foundation

@MainActor
final class PasteboardWatcher {
    private let environment: AppEnvironment
    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressedChanges = 0

    init(environment: AppEnvironment) {
        self.environment = environment
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suppressNextChange() {
        suppressedChanges += 1
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        if suppressedChanges > 0 {
            suppressedChanges -= 1
            return
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard environment.preferences.shouldCapture(bundleID: bundleID) else {
            return
        }

        guard let capture = ClipboardCapture.make(from: pasteboard, preferences: environment.preferences.state) else {
            return
        }

        environment.history.add(capture)
    }
}

private extension ClipboardCapture {
    static func make(from pasteboard: NSPasteboard, preferences: PreferencesState) -> ClipboardCapture? {
        if preferences.formatFileURL,
           let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
           ) as? [NSURL],
           !urls.isEmpty {
            let values = urls.compactMap(\.absoluteString)
            let title = values
                .compactMap { URL(string: $0)?.lastPathComponent }
                .joined(separator: ", ")
            return ClipboardCapture(
                kind: .fileURL,
                title: title.isEmpty ? L10n.string("history.files") : title,
                textValue: nil,
                fileURLs: values,
                data: nil,
                byteCount: values.joined().utf8.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue
            )
        }

        if preferences.formatURL,
           let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
           URL(string: urlString) != nil,
           urlString.contains("://") {
            return ClipboardCapture(
                kind: .url,
                title: urlString,
                textValue: urlString,
                fileURLs: [],
                data: nil,
                byteCount: urlString.utf8.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.URL.rawValue
            )
        }

        if preferences.formatPlainText,
           let string = pasteboard.string(forType: .string),
           !string.isEmpty {
            return ClipboardCapture(
                kind: .plainText,
                title: string,
                textValue: string,
                fileURLs: [],
                data: nil,
                byteCount: string.utf8.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.string.rawValue
            )
        }

        if preferences.formatRTF,
           let data = pasteboard.data(forType: .rtf),
           !data.isEmpty {
            return ClipboardCapture(
                kind: .richText,
                title: L10n.string("history.richText"),
                textValue: nil,
                fileURLs: [],
                data: data,
                byteCount: data.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue
            )
        }

        if preferences.formatRTFD,
           let data = pasteboard.data(forType: .rtfd),
           !data.isEmpty {
            return ClipboardCapture(
                kind: .rtfd,
                title: L10n.string("history.rtfd"),
                textValue: nil,
                fileURLs: [],
                data: data,
                byteCount: data.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.rtfd.rawValue
            )
        }

        if preferences.formatPDF,
           let data = pasteboard.data(forType: .pdf),
           !data.isEmpty {
            return ClipboardCapture(
                kind: .pdf,
                title: L10n.string("history.pdf"),
                textValue: nil,
                fileURLs: [],
                data: data,
                byteCount: data.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.pdf.rawValue
            )
        }

        if preferences.formatImage,
           let data = pasteboard.data(forType: .tiff),
           !data.isEmpty {
            return ClipboardCapture(
                kind: .image,
                title: L10n.string("history.image"),
                textValue: nil,
                fileURLs: [],
                data: data,
                byteCount: data.count,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.tiff.rawValue
            )
        }

        return nil
    }
}
