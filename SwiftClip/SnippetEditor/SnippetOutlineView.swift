import AppKit
import Combine
import SwiftUI

struct SnippetOutlineView: NSViewRepresentable {
    @ObservedObject var snippets: SnippetStore
    @Binding var selection: SnippetSelection?
    @Binding var expandedFolderIDs: Set<UUID>

    func makeCoordinator() -> Coordinator {
        Coordinator(
            snippets: snippets,
            selection: $selection,
            expandedFolderIDs: $expandedFolderIDs
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.floatsGroupRows = false
        outlineView.autosaveExpandedItems = false
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .clear
        outlineView.rowHeight = 24
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.registerForDraggedTypes([.swiftClipSnippetOutlineNode])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let column = NSTableColumn(identifier: .snippetOutlineColumn)
        column.minWidth = 120
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = outlineView

        context.coordinator.update(
            snippets: snippets,
            selection: $selection,
            expandedFolderIDs: $expandedFolderIDs,
            outlineView: outlineView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? NSOutlineView else {
            return
        }

        if let column = outlineView.tableColumns.first {
            column.width = max(scrollView.contentSize.width, column.minWidth)
        }

        context.coordinator.update(
            snippets: snippets,
            selection: $selection,
            expandedFolderIDs: $expandedFolderIDs,
            outlineView: outlineView
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let outlineView = scrollView.documentView as? NSOutlineView {
            outlineView.delegate = nil
            outlineView.dataSource = nil
        }
        coordinator.dismantle()
    }
}

@MainActor
extension SnippetOutlineView {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private var snippets: SnippetStore
        private var selection: Binding<SnippetSelection?>
        private var expandedFolderIDs: Binding<Set<UUID>>
        private weak var outlineView: NSOutlineView?
        private weak var subscribedStore: SnippetStore?
        private var changeCancellable: AnyCancellable?
        private var isReloadScheduled = false
        private var needsReload = true
        private var isApplyingExternalUpdate = false
        private var rootNodes: [SnippetOutlineNode] = []
        private var nodeByKey: [SnippetOutlineNode.Key: SnippetOutlineNode] = [:]
        private var folderByID: [UUID: SnippetSummary] = [:]
        private var snippetByKey: [SnippetOutlineNode.Key: SnippetLeaf] = [:]
        private var lastStructure: [OutlineSection] = []

        init(
            snippets: SnippetStore,
            selection: Binding<SnippetSelection?>,
            expandedFolderIDs: Binding<Set<UUID>>
        ) {
            self.snippets = snippets
            self.selection = selection
            self.expandedFolderIDs = expandedFolderIDs
            super.init()
            subscribe(to: snippets)
        }

        func update(
            snippets: SnippetStore,
            selection: Binding<SnippetSelection?>,
            expandedFolderIDs: Binding<Set<UUID>>,
            outlineView: NSOutlineView
        ) {
            self.snippets = snippets
            self.selection = selection
            self.expandedFolderIDs = expandedFolderIDs
            self.outlineView = outlineView
            subscribe(to: snippets)
            applyCurrentState(to: outlineView)
        }

        func dismantle() {
            changeCancellable?.cancel()
            changeCancellable = nil
            outlineView = nil
            subscribedStore = nil
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? SnippetOutlineNode else {
                return rootNodes.count
            }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? SnippetOutlineNode else {
                return rootNodes[index]
            }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? SnippetOutlineNode else {
                return false
            }
            return node.key.isFolder
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            objectValueFor tableColumn: NSTableColumn?,
            byItem item: Any?
        ) -> Any? {
            guard let node = item as? SnippetOutlineNode else {
                return nil
            }
            return title(for: node)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let node = item as? SnippetOutlineNode else {
                return nil
            }

            let cell = reusableCell(in: outlineView)
            cell.configure(
                title: title(for: node),
                systemImageName: systemImageName(for: node),
                isEnabled: isEnabled(node)
            )
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let outlineView = notification.object as? NSOutlineView else {
                return
            }

            let selectedRow = outlineView.selectedRow
            guard selectedRow >= 0,
                  let node = outlineView.item(atRow: selectedRow) as? SnippetOutlineNode else {
                selection.wrappedValue = nil
                return
            }

            selection.wrappedValue = selectionValue(for: node)
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            updateExpansion(from: notification, isExpanded: true)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            updateExpansion(from: notification, isExpanded: false)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> NSPasteboardWriting? {
            guard let node = item as? SnippetOutlineNode,
                  let payload = SnippetOutlineDragPayload(node: node),
                  let encodedPayload = payload.encodedString else {
                return nil
            }

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(encodedPayload, forType: .swiftClipSnippetOutlineNode)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex childIndex: Int
        ) -> NSDragOperation {
            guard let payload = SnippetOutlineDragPayload.decode(from: info.draggingPasteboard) else {
                return []
            }

            switch payload.kind {
            case .folder:
                guard let destination = folderDropDestination(
                    in: outlineView,
                    draggingInfo: info,
                    proposedItem: item,
                    proposedChildIndex: childIndex
                ),
                    isValidFolderDrop(folderID: payload.folderID, destination: destination) else {
                    return []
                }
                outlineView.setDropItem(nil, dropChildIndex: destination)
                return .move

            case .snippet:
                return validateSnippetDrop(
                    payload,
                    in: outlineView,
                    proposedItem: item,
                    proposedChildIndex: childIndex
                )
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex: Int
        ) -> Bool {
            guard let payload = SnippetOutlineDragPayload.decode(from: info.draggingPasteboard) else {
                return false
            }

            switch payload.kind {
            case .folder:
                guard let destination = folderDropDestination(
                    in: outlineView,
                    draggingInfo: info,
                    proposedItem: item,
                    proposedChildIndex: childIndex
                ),
                    isValidFolderDrop(folderID: payload.folderID, destination: destination) else {
                    return false
                }
                snippets.moveFolder(id: payload.folderID, toIndex: destination)
                selection.wrappedValue = .folder(payload.folderID)
                applyCurrentState(to: outlineView)
                return true

            case .snippet:
                guard let snippetID = payload.snippetID,
                      let target = snippetDropTarget(proposedItem: item, childIndex: childIndex) else {
                    return false
                }

                if payload.folderID == target.folderID {
                    guard let sourceIndex = target.folder.children.firstIndex(where: {
                        $0.key == .snippet(folderID: payload.folderID, snippetID: snippetID)
                    }) else {
                        return false
                    }

                    // Same-folder moves use SwiftUI-style offsets; cross-folder drops use the index reported by NSOutlineView.
                    snippets.moveSnippets(
                        in: target.folderID,
                        fromOffsets: IndexSet(integer: sourceIndex),
                        toOffset: target.childIndex
                    )
                } else if target.isAppendDrop {
                    snippets.moveSnippet(
                        snippetID: snippetID,
                        fromFolderID: payload.folderID,
                        toFolderID: target.folderID
                    )
                } else {
                    snippets.moveSnippet(
                        snippetID: snippetID,
                        fromFolderID: payload.folderID,
                        toFolderID: target.folderID,
                        toIndex: target.childIndex
                    )
                }

                expandedFolderIDs.wrappedValue.insert(target.folderID)
                selection.wrappedValue = .snippet(folderID: target.folderID, snippetID: snippetID)
                applyCurrentState(to: outlineView)
                if let targetNode = nodeByKey[.folder(target.folderID)] {
                    outlineView.expandItem(targetNode)
                }
                return true
            }
        }

        private func folderDropDestination(
            in outlineView: NSOutlineView,
            draggingInfo info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex childIndex: Int
        ) -> Int? {
            if item == nil {
                if childIndex == NSOutlineViewDropOnItemIndex {
                    return rootNodes.count
                }
                guard childIndex >= 0,
                      childIndex <= rootNodes.count else {
                    return nil
                }
                return childIndex
            }

            guard let proposedNode = item as? SnippetOutlineNode,
                  case .folder = proposedNode.key else {
                return nil
            }

            // Folder rows are root-only. Source-list outlines often propose drops
            // on a folder item; translate that row position back to a root index.
            return rootFolderDropIndex(
                in: outlineView,
                draggingInfo: info,
                overFolder: proposedNode
            )
        }

        private func rootFolderDropIndex(
            in outlineView: NSOutlineView,
            draggingInfo info: NSDraggingInfo,
            overFolder folder: SnippetOutlineNode
        ) -> Int? {
            let location = outlineView.convert(info.draggingLocation, from: nil)
            let folderRow = outlineView.row(forItem: folder)
            guard folderRow >= 0,
                  let folderIndex = rootNodes.firstIndex(where: { $0 === folder }) else {
                return nil
            }

            let row = outlineView.row(at: location)
            if row >= 0 {
                guard let rowNode = outlineView.item(atRow: row) as? SnippetOutlineNode,
                      rowNode === folder else {
                    return nil
                }
            }

            let rowRect = outlineView.rect(ofRow: folderRow)
            return location.y < rowRect.midY ? folderIndex : folderIndex + 1
        }

        private func isValidFolderDrop(folderID: UUID, destination: Int) -> Bool {
            guard destination >= 0,
                  destination <= rootNodes.count,
                  let sourceIndex = rootNodes.firstIndex(where: { $0.key == .folder(folderID) }) else {
                return false
            }

            return destination != sourceIndex && destination != sourceIndex + 1
        }

        private func subscribe(to store: SnippetStore) {
            guard store !== subscribedStore else {
                return
            }

            changeCancellable?.cancel()
            subscribedStore = store
            changeCancellable = store.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleReload()
                }
            }
        }

        private func scheduleReload() {
            needsReload = true
            guard !isReloadScheduled else {
                return
            }

            isReloadScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isReloadScheduled = false
                guard let outlineView = self.outlineView else {
                    return
                }
                self.applyCurrentState(to: outlineView)
            }
        }

        private func applyCurrentState(to outlineView: NSOutlineView) {
            let folders = snippets.allFolders()
            let structure = OutlineSection.sections(from: folders)
            rebuildTree(from: folders)

            let structureChanged = structure != lastStructure
            isApplyingExternalUpdate = true
            defer {
                isApplyingExternalUpdate = false
            }

            if structureChanged {
                outlineView.reloadData()
                lastStructure = structure
            } else if needsReload {
                reloadVisibleRows(in: outlineView)
            }
            needsReload = false

            applyExpandedState(to: outlineView)
            applySelectionState(to: outlineView)
        }

        private func rebuildTree(from folders: [SnippetSummary]) {
            var activeKeys = Set<SnippetOutlineNode.Key>()
            var nextRootNodes: [SnippetOutlineNode] = []
            var nextFolders: [UUID: SnippetSummary] = [:]
            var nextSnippets: [SnippetOutlineNode.Key: SnippetLeaf] = [:]

            for folder in folders {
                let folderKey = SnippetOutlineNode.Key.folder(folder.id)
                let folderNode = node(for: folderKey)
                folderNode.parent = nil
                folderNode.children = []
                activeKeys.insert(folderKey)
                nextFolders[folder.id] = folder

                for snippet in folder.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                    let snippetKey = SnippetOutlineNode.Key.snippet(folderID: folder.id, snippetID: snippet.id)
                    let snippetNode = node(for: snippetKey)
                    snippetNode.parent = folderNode
                    snippetNode.children = []
                    folderNode.children.append(snippetNode)
                    activeKeys.insert(snippetKey)
                    nextSnippets[snippetKey] = snippet
                }

                nextRootNodes.append(folderNode)
            }

            nodeByKey = nodeByKey.filter { activeKeys.contains($0.key) }
            rootNodes = nextRootNodes
            folderByID = nextFolders
            snippetByKey = nextSnippets
        }

        private func node(for key: SnippetOutlineNode.Key) -> SnippetOutlineNode {
            if let node = nodeByKey[key] {
                return node
            }

            let node = SnippetOutlineNode(key: key)
            nodeByKey[key] = node
            return node
        }

        private func reloadVisibleRows(in outlineView: NSOutlineView) {
            let visibleRange = outlineView.rows(in: outlineView.visibleRect)
            guard visibleRange.length > 0,
                  !outlineView.tableColumns.isEmpty else {
                return
            }

            let rows = IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length))
            let columns = IndexSet(integer: 0)
            outlineView.reloadData(forRowIndexes: rows, columnIndexes: columns)
        }

        private func applyExpandedState(to outlineView: NSOutlineView) {
            for node in rootNodes {
                guard case .folder(let folderID) = node.key else {
                    continue
                }

                if expandedFolderIDs.wrappedValue.contains(folderID) {
                    outlineView.expandItem(node)
                } else {
                    outlineView.collapseItem(node)
                }
            }
        }

        private func applySelectionState(to outlineView: NSOutlineView) {
            guard let selectionNode = node(for: selection.wrappedValue),
                  outlineView.row(forItem: selectionNode) >= 0 else {
                outlineView.deselectAll(nil)
                return
            }

            let row = outlineView.row(forItem: selectionNode)
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func node(for selection: SnippetSelection?) -> SnippetOutlineNode? {
            switch selection {
            case .folder(let folderID):
                return nodeByKey[.folder(folderID)]
            case .snippet(let folderID, let snippetID):
                return nodeByKey[.snippet(folderID: folderID, snippetID: snippetID)]
            case nil:
                return nil
            }
        }

        private func selectionValue(for node: SnippetOutlineNode) -> SnippetSelection {
            switch node.key {
            case .folder(let folderID):
                return .folder(folderID)
            case .snippet(let folderID, let snippetID):
                return .snippet(folderID: folderID, snippetID: snippetID)
            }
        }

        private func updateExpansion(from notification: Notification, isExpanded: Bool) {
            guard !isApplyingExternalUpdate,
                  let node = notification.userInfo?["NSObject"] as? SnippetOutlineNode,
                  case .folder(let folderID) = node.key else {
                return
            }

            if isExpanded {
                expandedFolderIDs.wrappedValue.insert(folderID)
            } else {
                expandedFolderIDs.wrappedValue.remove(folderID)
            }
        }

        private func reusableCell(in outlineView: NSOutlineView) -> SnippetOutlineCellView {
            let identifier = NSUserInterfaceItemIdentifier.snippetOutlineCell
            if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SnippetOutlineCellView {
                return cell
            }

            let cell = SnippetOutlineCellView()
            cell.identifier = identifier
            return cell
        }

        private func systemImageName(for node: SnippetOutlineNode) -> String {
            switch node.key {
            case .folder:
                return "folder"
            case .snippet:
                return "text.alignleft"
            }
        }

        private func title(for node: SnippetOutlineNode) -> String {
            switch node.key {
            case .folder(let folderID):
                return folderByID[folderID]?.title ?? ""
            case .snippet:
                return snippetByKey[node.key]?.title ?? ""
            }
        }

        private func isEnabled(_ node: SnippetOutlineNode) -> Bool {
            switch node.key {
            case .folder(let folderID):
                return folderByID[folderID]?.isEnabled ?? false
            case .snippet:
                return snippetByKey[node.key]?.isEnabled ?? false
            }
        }

        private func validateSnippetDrop(
            _ payload: SnippetOutlineDragPayload,
            in outlineView: NSOutlineView,
            proposedItem item: Any?,
            proposedChildIndex childIndex: Int
        ) -> NSDragOperation {
            guard let snippetID = payload.snippetID else {
                return []
            }

            if let proposedNode = item as? SnippetOutlineNode {
                switch proposedNode.key {
                case .folder:
                    let targetIndex = childIndex == NSOutlineViewDropOnItemIndex
                        ? proposedNode.children.count
                        : childIndex
                    guard isValidSnippetDrop(
                        snippetID: snippetID,
                        fromFolderID: payload.folderID,
                        toFolder: proposedNode,
                        childIndex: targetIndex
                    ) else {
                        return []
                    }
                    return .move

                case .snippet(_, let proposedSnippetID):
                    guard snippetID != proposedSnippetID,
                          let parent = proposedNode.parent,
                          let targetIndex = parent.children.firstIndex(where: { $0 === proposedNode }),
                          isValidSnippetDrop(
                            snippetID: snippetID,
                            fromFolderID: payload.folderID,
                            toFolder: parent,
                            childIndex: targetIndex
                          ) else {
                        return []
                    }
                    outlineView.setDropItem(parent, dropChildIndex: targetIndex)
                    return .move
                }
            }

            return []
        }

        private func isValidSnippetDrop(
            snippetID: UUID,
            fromFolderID: UUID,
            toFolder folder: SnippetOutlineNode,
            childIndex: Int
        ) -> Bool {
            guard case .folder(let targetFolderID) = folder.key,
                  childIndex >= 0,
                  childIndex <= folder.children.count else {
                return false
            }

            if fromFolderID == targetFolderID,
               let sourceIndex = folder.children.firstIndex(where: {
                   $0.key == .snippet(folderID: fromFolderID, snippetID: snippetID)
               }),
               (childIndex == sourceIndex || childIndex == sourceIndex + 1) {
                return false
            }

            return true
        }

        private func snippetDropTarget(
            proposedItem item: Any?,
            childIndex: Int
        ) -> SnippetDropTarget? {
            if let folder = item as? SnippetOutlineNode,
               case .folder(let folderID) = folder.key {
                let targetIndex = childIndex == NSOutlineViewDropOnItemIndex ? folder.children.count : childIndex
                return SnippetDropTarget(
                    folder: folder,
                    folderID: folderID,
                    childIndex: targetIndex,
                    isAppendDrop: childIndex == NSOutlineViewDropOnItemIndex
                )
            }

            if let snippet = item as? SnippetOutlineNode,
               case .snippet = snippet.key,
               let folder = snippet.parent,
               case .folder(let folderID) = folder.key,
               let targetIndex = folder.children.firstIndex(where: { $0 === snippet }) {
                return SnippetDropTarget(
                    folder: folder,
                    folderID: folderID,
                    childIndex: targetIndex,
                    isAppendDrop: false
                )
            }

            return nil
        }
    }
}

private final class SnippetOutlineCellView: NSTableCellView {
    private let hostingView = NSHostingView(
        rootView: SnippetOutlineRowView(title: "", systemImageName: "folder", isEnabled: true)
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHostingView()
    }

    func configure(title: String, systemImageName: String, isEnabled: Bool) {
        hostingView.rootView = SnippetOutlineRowView(
            title: title,
            systemImageName: systemImageName,
            isEnabled: isEnabled
        )
    }

    private func setupHostingView() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            hostingView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private struct SnippetOutlineRowView: View {
    let title: String
    let systemImageName: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImageName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: NSFont.systemFontSize))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private final class SnippetOutlineNode: NSObject {
    enum Key: Hashable {
        case folder(UUID)
        case snippet(folderID: UUID, snippetID: UUID)

        var isFolder: Bool {
            if case .folder = self {
                return true
            }
            return false
        }
    }

    let key: Key
    weak var parent: SnippetOutlineNode?
    var children: [SnippetOutlineNode] = []

    init(key: Key) {
        self.key = key
    }
}

private struct OutlineSection: Equatable {
    let folderID: UUID
    let snippetIDs: [UUID]

    static func sections(from folders: [SnippetSummary]) -> [Self] {
        folders.map { folder in
            OutlineSection(
                folderID: folder.id,
                snippetIDs: folder.snippets
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map(\.id)
            )
        }
    }
}

private struct SnippetDropTarget {
    let folder: SnippetOutlineNode
    let folderID: UUID
    let childIndex: Int
    let isAppendDrop: Bool
}

private struct SnippetOutlineDragPayload: Codable {
    enum Kind: String, Codable {
        case folder
        case snippet
    }

    let kind: Kind
    let folderID: UUID
    let snippetID: UUID?

    var encodedString: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    init(kind: Kind, folderID: UUID, snippetID: UUID?) {
        self.kind = kind
        self.folderID = folderID
        self.snippetID = snippetID
    }

    init?(node: SnippetOutlineNode) {
        switch node.key {
        case .folder(let folderID):
            self.init(kind: .folder, folderID: folderID, snippetID: nil)
        case .snippet(let folderID, let snippetID):
            self.init(kind: .snippet, folderID: folderID, snippetID: snippetID)
        }
    }

    static func decode(from pasteboard: NSPasteboard) -> Self? {
        let strings = pasteboard.pasteboardItems?.compactMap {
            $0.string(forType: .swiftClipSnippetOutlineNode)
        } ?? []

        for string in strings {
            guard let data = string.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Self.self, from: data) else {
                continue
            }
            return payload
        }

        guard let string = pasteboard.string(forType: .swiftClipSnippetOutlineNode),
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

private extension NSPasteboard.PasteboardType {
    static let swiftClipSnippetOutlineNode = NSPasteboard.PasteboardType("app.swiftclip.snippet-outline-node")
}

private extension NSUserInterfaceItemIdentifier {
    static let snippetOutlineColumn = NSUserInterfaceItemIdentifier("SnippetOutlineColumn")
    static let snippetOutlineCell = NSUserInterfaceItemIdentifier("SnippetOutlineCell")
}
