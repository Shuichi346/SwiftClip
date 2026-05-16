# Task: Replace SwiftUI `List`-based Snippet Outline with `NSOutlineView`

## Context

The SwiftUI `List` + `DisclosureGroup` implementation in `SwiftClip/SnippetEditor/SnippetOutlineView.swift` cannot reliably handle drag-and-drop of snippets across folders. This is a known SwiftUI limitation (drops over `List` are unreliable; cross-section/cross-group `.onMove` is not supported). We are replacing it with an `NSOutlineView` wrapped via `NSViewRepresentable`, matching Clipy's original approach.

The store layer (`SnippetStore`) is already correct and unit-tested (`SnippetStoreReorderingTests`). **Do not modify `SnippetStore`, `Snippet`, `SnippetFolder`, `SnippetSummary`, or `SnippetLeaf`.** All UI changes must continue to call the existing store methods: `moveFolder(id:toIndex:)`, `moveFolders(fromOffsets:toOffset:)`, `moveSnippets(in:fromOffsets:toOffset:)`, and `moveSnippet(snippetID:fromFolderID:toFolderID:toIndex:)`.

## Goal

Working drag-and-drop in the snippet editor sidebar for all four cases:

1. Reorder folders at the root level.
2. Reorder snippets within the same folder.
3. Move a snippet from one folder to another (the currently broken case).
4. Drop a snippet onto a folder row (append to that folder).

Selection, expand/collapse state, and the existing toolbar (`SnippetToolbar`) must continue to work without changes to `SnippetToolbar.swift` beyond what is strictly required to bridge selection.

## Files to Change

- **Replace** `SwiftClip/SnippetEditor/SnippetOutlineView.swift` with an `NSViewRepresentable` wrapping `NSOutlineView`.
- **Update** `SwiftClip/SnippetEditor/SnippetEditorWindow.swift` only if signatures of the outline view change. Keep `SnippetSelection` as-is.
- **Remove** the `UTExportedTypeDeclarations` entry for `app.swiftclip.snippet-outline-item` in `SwiftClip/Resources/Info.plist` (no longer needed).
- **Do not** touch `SnippetDetailPane.swift`, `SnippetToolbar.swift`, `SnippetStore.swift`, or any test file.

## Implementation Requirements

### 1. NSViewRepresentable wrapper

Create a `SnippetOutlineView: NSViewRepresentable` that exposes the same public API the rest of the app expects:

- `@ObservedObject var snippets: SnippetStore`
- `@Binding var selection: SnippetSelection?`
- `@Binding var expandedFolderIDs: Set<UUID>`

Internally it owns an `NSScrollView` containing an `NSOutlineView` configured as a source list (`.sourceList` selection highlight style, single column, no headers, `floatsGroupRows = false`, `autosaveExpandedItems = false`).

In `updateNSView`, diff the store's folders against the outline's current data, call `reloadData()` only when structure changes (compare a hash of folder IDs + snippet IDs + ordering), and re-apply expansion + selection state from the bindings without causing feedback loops (guard with an `isApplyingExternalUpdate` flag in the coordinator).

### 2. Item model for the outline

Use a reference-type wrapper (`final class SnippetOutlineNode`) so `NSOutlineView` can compare items by identity. Each node holds either a `folderID: UUID` or a `(folderID: UUID, snippetID: UUID)` pair, plus a parent reference. Rebuild the node tree from `snippets.allFolders()` whenever the store publishes a change. Keep a dictionary `[NodeKey: SnippetOutlineNode]` so the same node instance survives across reloads (this is what lets `NSOutlineView` preserve expansion/selection visually).

### 3. Coordinator responsibilities

Implement a `Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate` that:

- Provides children counts and items from the node tree.
- Returns `true` from `isItemExpandable` only for folder nodes.
- Returns a configured `NSTableCellView` from `outlineView(_:viewFor:item:)` with an `NSImageView` (folder or `text.alignleft` SF Symbol) and an `NSTextField` showing the title. Dim disabled items via `textField.textColor = .secondaryLabelColor`.
- Handles `outlineViewSelectionDidChange` by translating the selected row to a `SnippetSelection` and writing back through the binding.
- Handles `outlineViewItemDidExpand` / `outlineViewItemDidCollapse` to keep `expandedFolderIDs` in sync.

### 4. Drag and drop

This is the core of the migration. Implement these `NSOutlineViewDataSource` methods:

- `outlineView(_:pasteboardWriterForItem:)` returns an `NSPasteboardItem` whose property list under a custom pasteboard type (e.g. `NSPasteboard.PasteboardType("app.swiftclip.snippet-outline-node")`) encodes a small JSON dictionary: `{"kind":"folder|snippet","folderID":"…","snippetID":"…?"}`. Register this type with `outlineView.registerForDraggedTypes([...])` in `makeNSView`.
- `outlineView(_:validateDrop:proposedItem:proposedChildIndex:)`:
  - Reject dropping a folder onto/inside another folder (folders are root-level only). For folder drags, only allow drops where `proposedItem == nil` (root) and `proposedChildIndex >= 0`; if `proposedChildIndex == NSOutlineViewDropOnItemIndex`, call `setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)` to retarget — actually just return `[]` in that case.
  - For snippet drags: allow drop on a folder node (between-rows or on-the-row both produce a valid target). If `proposedItem` is a snippet, retarget via `outlineView.setDropItem(parentFolderNode, dropChildIndex: indexOfThatSnippet)` so the user can drop between snippet rows.
  - Reject dropping a snippet onto itself or a folder onto itself (no-op).
  - Return `.move` for valid cases, `[]` otherwise.
- `outlineView(_:acceptDrop:item:childIndex:)`:
  - Decode the pasteboard payload.
  - For a folder payload: call `snippets.moveFolder(id:toIndex:)` with the corrected destination index (handle `childIndex == -1` as "append to end").
  - For a snippet payload onto a folder node with `childIndex == -1`: call `snippets.moveSnippet(snippetID:fromFolderID:toFolderID:)` with no `toIndex` (append).
  - For a snippet payload onto a folder node with a specific `childIndex`: call `snippets.moveSnippet(snippetID:fromFolderID:toFolderID:toIndex: childIndex)`.
  - After the store mutation, set the new selection and ensure the destination folder is expanded (update both the binding and call `outlineView.expandItem(...)`).
  - Return `true`.

### 5. Index adjustment rules

When the user drags a snippet *down* within the same folder, `NSOutlineView` reports the destination index *before* the source is removed. The existing `SnippetStore.moveSnippet(...toIndex:)` already normalizes after removal, so pass `childIndex` through unchanged for cross-folder moves. For same-folder reorders, route through `snippets.moveSnippets(in:fromOffsets:toOffset:)` to reuse the SwiftUI-style offset semantics that the tests already cover. Document this branching with a short comment.

### 6. Avoiding update loops

The coordinator must distinguish between:

- Selection changes initiated by the user (write to binding).
- Selection changes caused by `updateNSView` re-applying the binding (do not write back).

Use a single `isApplyingExternalUpdate: Bool` flag that wraps each `reloadData`, `expandItem`, `selectRowIndexes` block.

### 7. Combine subscription

In the coordinator, subscribe to `snippets.objectWillChange` and call `needsReload = true` then schedule a single `DispatchQueue.main.async` reload to coalesce bursts of updates from the store. Cancel the subscription in `dismantleNSView`.

### 8. Info.plist cleanup

Remove the `UTExportedTypeDeclarations` array from `SwiftClip/Resources/Info.plist`. The new pasteboard type is a private app-internal type and does not need UTI declaration.

## Out of Scope

- Do not change snippet/folder data models.
- Do not change `SnippetStore` behavior or method signatures.
- Do not change the toolbar, detail pane, menu bar, or any localization strings.
- Do not add new third-party dependencies.

## Verification Steps

After implementation, the agent must:

1. Build with the existing command:
   ```
   xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath /private/tmp/swiftclip-derived \
     CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
   ```
2. Run the test suite (same command with `test` instead of `build`) and confirm `SnippetStoreReorderingTests` still pass unchanged.
3. Launch via `./script/build_and_run.sh --verify` and manually confirm:
   - Folders can be reordered at root.
   - Snippets can be reordered within a folder.
   - A snippet can be dragged from folder A and dropped on folder B (the previously broken case).
   - A snippet can be dragged into a specific position between snippets in another folder.
   - Selection in the sidebar still drives the detail pane.
   - Folder expansion state survives store mutations.
   - Toolbar Add/Delete/Import/Export still operate on the current selection.

## Deliverables

- Rewritten `SnippetOutlineView.swift`.
- Minimal touch-ups to `SnippetEditorWindow.swift` only if required by the new API surface.
- Updated `Info.plist` with the UTI declaration removed.
- A short note appended to `CHANGELOG.md` under `[Unreleased]` describing the migration to `NSOutlineView` and that cross-folder snippet drag-and-drop now works reliably.