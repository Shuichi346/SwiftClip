import AppKit
import Foundation

@MainActor
final class PasteboardWatcher {
    private let environment: AppEnvironment
    private var timer: Timer?
    private var lastChangeCount: Int
    private var selfCaptureFilter = PasteboardChangeFilter()

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

    func suppressChange(_ changeCount: Int) {
        selfCaptureFilter.recordSelfWrite(changeCount: changeCount)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        if selfCaptureFilter.shouldSuppress(observedChangeCount: lastChangeCount) {
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

struct PasteboardChangeFilter {
    private var selfWriteChangeCounts: Set<Int> = []

    mutating func recordSelfWrite(changeCount: Int) {
        selfWriteChangeCounts.insert(changeCount)
    }

    mutating func shouldSuppress(observedChangeCount: Int) -> Bool {
        let shouldSuppress = selfWriteChangeCounts.remove(observedChangeCount) != nil
        selfWriteChangeCounts = selfWriteChangeCounts.filter { $0 > observedChangeCount }
        return shouldSuppress
    }
}

extension ClipboardCapture {
    static let titlePreviewLimit = 120
    static let inlineTextByteLimit = 64 * 1024

    static func make(from pasteboard: NSPasteboard, preferences: PreferencesState) -> ClipboardCapture? {
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
                title: (title.isEmpty ? L10n.string("history.files") : title)
                    .swiftClipTruncated(to: titlePreviewLimit),
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
            return textCapture(
                kind: .url,
                string: urlString,
                pasteboardType: .URL
            )
        }

        if preferences.formatPlainText,
           let string = pasteboard.string(forType: .string),
           !string.isEmpty {
            return textCapture(
                kind: .plainText,
                string: string,
                pasteboardType: .string
            )
        }

        return nil
    }

    private static func textCapture(
        kind: ClipboardItemKind,
        string: String,
        pasteboardType: NSPasteboard.PasteboardType
    ) -> ClipboardCapture {
        let data = Data(string.utf8)
        let storesPayloadInBlob = data.count > inlineTextByteLimit
        return ClipboardCapture(
            kind: kind,
            title: string.swiftClipTruncated(to: titlePreviewLimit),
            textValue: storesPayloadInBlob ? nil : string,
            fileURLs: [],
            data: storesPayloadInBlob ? data : nil,
            byteCount: data.count,
            pasteboardTypeIdentifier: pasteboardType.rawValue
        )
    }
}
