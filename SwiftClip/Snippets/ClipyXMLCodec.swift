import Foundation

enum ClipyXMLCodec {
    static func decode(data: Data) throws -> [SnippetSummary] {
        let delegate = ClipyXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? L10n.string("error.xmlUnknown")
            throw SwiftClipError.xmlParseFailed(message)
        }

        return delegate.folders
    }

    static func encode(folders: [SnippetSummary]) throws -> Data {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="utf-8" standalone="no"?>"#,
            "<folders>"
        ]

        for folder in folders.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            lines.append("\t<folder>")
            lines.append("\t\t<title>\(escape(folder.title))</title>")
            lines.append("\t\t<snippets>")

            for snippet in folder.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                lines.append("\t\t\t<snippet>")
                lines.append("\t\t\t\t<title>\(escape(snippet.title))</title>")
                lines.append("\t\t\t\t<content>\(escape(snippet.content, encodeNewlines: true))</content>")
                lines.append("\t\t\t</snippet>")
            }

            lines.append("\t\t</snippets>")
            lines.append("\t</folder>")
        }

        lines.append("</folders>")
        let xml = lines.joined(separator: "\n") + "\n"

        guard let data = xml.data(using: .utf8) else {
            throw SwiftClipError.xmlEncodeFailed(L10n.string("error.xmlEncodeFailed"))
        }
        return data
    }

    private static func escape(_ string: String, encodeNewlines: Bool = false) -> String {
        var escaped = string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        if encodeNewlines {
            escaped = escaped.replacingOccurrences(of: "\n", with: "&#10;")
        }

        return escaped
    }
}

private final class ClipyXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var folders: [SnippetSummary] = []

    private var text = ""
    private var currentFolderTitle = ""
    private var currentSnippets: [SnippetLeaf] = []
    private var currentSnippetTitle = ""
    private var currentSnippetContent = ""
    private var isInsideSnippet = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""

        if elementName == "folder" {
            currentFolderTitle = ""
            currentSnippets = []
        } else if elementName == "snippet" {
            isInsideSnippet = true
            currentSnippetTitle = ""
            currentSnippetContent = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "title" where isInsideSnippet:
            currentSnippetTitle = text
        case "title":
            currentFolderTitle = text
        case "content":
            currentSnippetContent = text
        case "snippet":
            currentSnippets.append(
                SnippetLeaf(
                    title: currentSnippetTitle,
                    content: currentSnippetContent,
                    sortIndex: currentSnippets.count
                )
            )
            isInsideSnippet = false
        case "folder":
            folders.append(
                SnippetSummary(
                    title: currentFolderTitle,
                    sortIndex: folders.count,
                    snippets: currentSnippets
                )
            )
        default:
            break
        }

        text = ""
    }
}
