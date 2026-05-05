import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SnippetToolbar: ToolbarContent {
    let environment: AppEnvironment
    @Binding var selection: SnippetSelection?
    @Binding var expandedFolderIDs: Set<UUID>

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                addSnippet()
            } label: {
                Image(systemName: "note.text.badge.plus")
            }
            .help(L10n.string("editor.toolbar.addSnippet"))

            Button {
                addFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help(L10n.string("editor.toolbar.addFolder"))

            Button {
                deleteSelection()
            } label: {
                Image(systemName: "minus.circle")
            }
            .help(L10n.string("editor.toolbar.delete"))

            Button {
                toggleSelection()
            } label: {
                Image(systemName: "switch.2")
            }
            .help(L10n.string("editor.toolbar.toggleEnabled"))

            Button {
                importXML()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help(L10n.string("editor.toolbar.import"))

            Button {
                exportXML()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(L10n.string("editor.toolbar.export"))
        }
    }

    private func addFolder() {
        let id = environment.snippets.addFolder()
        expandedFolderIDs.insert(id)
        selection = .folder(id)
    }

    private func addSnippet() {
        let folderID = selectedFolderID()
        guard let snippetID = environment.snippets.addSnippet(to: folderID) else {
            return
        }

        let resolvedFolderID = folderID ?? environment.snippets.allFolders().first?.id
        guard let resolvedFolderID else {
            return
        }

        expandedFolderIDs.insert(resolvedFolderID)
        selection = .snippet(folderID: resolvedFolderID, snippetID: snippetID)
    }

    private func deleteSelection() {
        guard let selection else {
            return
        }

        switch selection {
        case .folder(let folderID):
            guard DeleteConfirmationAlert.confirm(kind: .folder) else {
                return
            }
            environment.snippets.deleteFolder(id: folderID)
            self.selection = nil
        case .snippet(let folderID, let snippetID):
            guard DeleteConfirmationAlert.confirm(kind: .snippet) else {
                return
            }
            environment.snippets.deleteSnippet(folderID: folderID, snippetID: snippetID)
            self.selection = .folder(folderID)
        }
    }

    private func toggleSelection() {
        guard let selection else {
            return
        }

        switch selection {
        case .folder(let folderID):
            guard let folder = environment.snippets.folder(id: folderID) else {
                return
            }
            environment.snippets.updateFolder(id: folderID, isEnabled: !folder.isEnabled)
        case .snippet(let folderID, let snippetID):
            guard let snippet = environment.snippets.snippet(folderID: folderID, snippetID: snippetID) else {
                return
            }
            environment.snippets.updateSnippet(folderID: folderID, snippetID: snippetID, isEnabled: !snippet.isEnabled)
        }
    }

    private func importXML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let importedFolders = try ClipyXMLCodec.decode(data: data)
            switch importMode() {
            case .replace:
                try environment.snippets.replaceAll(with: importedFolders)
            case .append:
                environment.snippets.append(importedFolders)
            case .cancel:
                return
            }
        } catch {
            showError(error)
        }
    }

    private func exportXML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "swiftclip-snippets.xml"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try ClipyXMLCodec.encode(folders: environment.snippets.allFolders())
            try data.write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    private enum ImportMode {
        case replace
        case append
        case cancel
    }

    private func importMode() -> ImportMode {
        let alert = NSAlert()
        alert.messageText = L10n.string("editor.import.title")
        alert.informativeText = L10n.string("editor.import.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("editor.import.replace"))
        alert.addButton(withTitle: L10n.string("editor.import.append"))
        alert.addButton(withTitle: L10n.string("editor.import.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .append
        default:
            return .cancel
        }
    }

    private func selectedFolderID() -> UUID? {
        switch selection {
        case .folder(let folderID):
            return folderID
        case .snippet(let folderID, _):
            return folderID
        case nil:
            return nil
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
