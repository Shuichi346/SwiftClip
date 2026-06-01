# SwiftClip Handoff Notes

Last updated: 2026-06-01

## Implementation Context

- The app was created from `PLANS.md` as a macOS 26+ SwiftUI/AppKit menu-bar clipboard manager.
- The primary project is `SwiftClip.xcodeproj`.
- The app uses `KeyboardShortcuts` from `https://github.com/sindresorhus/KeyboardShortcuts.git`, pinned from version `2.4.0`.
- The bundle identifier used by the generated project is `app.swiftclip.SwiftClip`.
- The app is configured as a menu-bar accessory app with `LSUIElement = true`.
- The app icon is `SwiftClip/Resources/AppIcon.icns`, referenced from `Resources/Info.plist` as `CFBundleIconFile = AppIcon`.
- The `Main` global shortcut opens a standalone History/Snippets popup next to the cursor. It intentionally does not invoke the menu-bar status item.
- The Extensions preferences tab now exposes only the plain-text paste trigger. Delete-on-select and delete-after-paste preferences and shortcut names were removed, and selecting a history item no longer removes it through those settings.

## Problems Encountered And Fixes

### Snippet editor sidebar auto-collapsed when dragged narrow

The snippet editor used `NavigationSplitView` with a sidebar width minimum, but the backing macOS split view could still switch the sidebar column into a hidden collapsed state when the divider crossed AppKit's collapse threshold.

Solution:
- Replaced the editor root `NavigationSplitView` with `HSplitView`, which has no sidebar auto-collapse feature.
- Kept the current initial sidebar width as `idealWidth = 200`, with `minWidth = 180` and `maxWidth = 220`.
- Hosted outline row labels in SwiftUI and applied `.lineLimit(1)` plus `.fixedSize(horizontal: true, vertical: false)` to folder and snippet title text.
- Verified with an Xcode MCP build, command-line XCTest, and `./script/build_and_run.sh --verify`.

### Standalone popup reserved shortcut-column width

The standalone History/Snippets popup inherited the `SwiftClipを終了` `⌘Q` key equivalent from the menu-bar action section. AppKit reserved a keyboard-shortcut column across the whole `NSMenu`, which left extra blank space between snippet folder titles and submenu arrows.

Solution:
- Added a `showsQuitShortcut` option to `ActionMenuSection.add`.
- The menu-bar menu keeps `⌘Q`; the standalone popup calls the action section with `showsQuitShortcut: false`.

### Detached JSON persistence could write stale snapshots last

History, snippet, and preferences stores previously wrote JSON snapshots from independent detached tasks. Rapid updates could allow an older snapshot to finish after a newer one, leaving stale persisted state on disk.

Solution:
- Added `JSONPersistenceQueue`, a serial utility queue for ordered JSON snapshot writes.
- Routed `HistoryStore`, `SnippetStore`, and `PreferencesStore` persistence through that queue while keeping writes off the main actor.
- Added `JSONPersistenceQueueTests.testWritesSnapshotsInEnqueueOrder()` to verify final disk state follows enqueue order.

### History paste failures cleared the pasteboard

History item paste handling cleared `NSPasteboard.general` before proving the new item could be written. Invalid file URL history entries or missing blob data could erase the existing clipboard and still drive paste-related side effects.

Solution:
- Validate file URL history payloads before clearing the pasteboard.
- Read blob data before clearing the pasteboard.
- Check `NSPasteboard` write return values for text, files, and blob data before calling `onPasteboardWrite`.
- Added `SnippetAttachmentTests.testPasteHistoryItemIgnoresInvalidFileURLs()` to assert failed file URL writes leave the existing pasteboard unchanged.

### Snippet load did not canonicalize nested sort indexes

Snippet folders were sorted on load, but nested snippets kept the raw persisted array order even when `sortIndex` values disagreed.

Solution:
- Normalize loaded folders and snippets by stable `sortIndex` order.
- Keep `SnippetStore.allFolders()` as a direct snapshot read after load/mutation normalization instead of re-sorting every call.
- Added `SnippetStoreReorderingTests.testLoadNormalizesFolderAndSnippetSortIndexes()`.

### Xcode test action reported no results

The Xcode MCP `RunAllTests` action listed all tests as `No result` in this session, despite the project building. The command-line test run executed normally.

Solution/status:
- Used the repo-approved `xcodebuild ... test` command for actual test execution.
- `xcodebuild` reported `** TEST SUCCEEDED **` for 22 tests.
- During the first refactor build, `SnippetStore.normalized` briefly missed an explicit `return` in a multi-statement closure; the compile error was fixed before final verification.

### Mixed text-and-attachment snippet pastes split in chat fields

Mixed snippets with text and an image attachment were pasted by some receivers as image-only, while text-only apps pasted only the text. This matched receivers choosing one representation or route from a mixed pasteboard payload rather than treating it as a complete snippet.

Solution:
- Write snippet text and file attachments as separate pasteboard items in `PasteEngine`.
- For bundle IDs listed in the Mixed Snippet Paste Apps preference, paste text first and then paste attachments after a short delay so file-upload chat fields can receive both.
- Keep the preference empty by default; users explicitly add apps that need the two-step workaround.
- App-list preferences use an `NSOpenPanel` app picker and extract `Bundle(url:)?.bundleIdentifier` from selected `.app` bundles.
- Keep `SnippetAttachmentTests.testPasteSnippetWritesTextAndAttachmentsAsSeparatePasteboardItems()` to assert the multi-item pasteboard structure.

### Sandbox writes outside the active worktree

Creating `.codex/environments/environment.toml` failed when the active writable root did not include the target directory.

Solution:
- Re-run the file creation from the correct checkout, or request sandbox escalation for the write.
- Keep `.codex/environments/environment.toml` in the repo so future Codex runs have the intended build command available.

### No Xcode project was open

The machine instructions prefer using the Xcode MCP server when an Xcode project is already open. No active Xcode project was available during implementation.

Solution:
- Used `xcodebuild` as the fallback, which is allowed when no project is open.
- Re-run builds with:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

### KeyboardShortcuts dependency resolution

The package dependency needed network access the first time `xcodebuild -list` resolved packages.

Solution:
- `xcodebuild -list -project SwiftClip.xcodeproj` successfully resolved the package.
- If package resolution fails in a fresh environment, retry with network permission or open the project in Xcode and resolve packages there.

### `FoundationXML` import failure

The Clipy XML import/export code initially imported `FoundationXML`, which failed in the Xcode macOS app build.

Solution:
- Removed `FoundationXML` and used `Foundation.XMLParser` APIs from `Foundation`.
- The XML codec tests cover folder/snippet round-tripping and newline escaping.

### Accessibility prompt concurrency issue

Using `kAXTrustedCheckOptionPrompt` directly caused Swift 6 strict concurrency/type-conversion diagnostics.

Solution:
- Use the literal key string `"AXTrustedCheckOptionPrompt"` when building the `AXIsProcessTrustedWithOptions` dictionary.
- This keeps `PermissionsProbe` concurrency-safe under strict Swift 6 settings.

### `Info.plist` copied as a resource

The first synchronized Xcode project setup copied `Resources/Info.plist` into the app bundle as a resource, producing a build warning.

Solution:
- Added a `PBXFileSystemSynchronizedBuildFileExceptionSet` exclusion for `Resources/Info.plist`.
- Also excluded `Resources/SwiftClip.entitlements` from resources.

### AppIntents metadata warning

Xcode still emits:

```text
warning: Metadata extraction skipped. No AppIntents.framework dependency found.
```

Solution/status:
- The app does not use AppIntents.
- Added `OTHER_SWIFT_FLAGS = "$(inherited) -Xfrontend -disable-autolink-framework -Xfrontend AppIntents"` to the app target, but Xcode still emits the non-fatal metadata warning.
- Debug and Release builds succeed. Treat this as residual Xcode metadata noise unless it becomes a hard failure.

### Release warnings-as-errors applied too broadly

Passing `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the `xcodebuild` command line applied it to the `KeyboardShortcuts` package target and conflicted with that package's `-suppress-warnings` flag:

```text
conflicting options '-warnings-as-errors' and '-suppress-warnings'
```

Solution:
- Do not pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` globally on the command line.
- Configure warnings-as-errors only on the `SwiftClip` app target Release build settings.

### GUI launch verification needs elevated execution

Launching the built `.app` and checking for the process can fail inside the sandbox due to process-service restrictions.

Solution:
- Use the provided script and allow GUI/process escalation when prompted:

```sh
./script/build_and_run.sh --verify
```

### App icon was not packaged

The app icon existed at the repository root as `icon.icns`, but Xcode builds did not use it as the application bundle icon.

Solution:
- Move it to `SwiftClip/Resources/AppIcon.icns`.
- Add `CFBundleIconFile = AppIcon` to `SwiftClip/Resources/Info.plist`.
- With synchronized Xcode file groups, the `.icns` file is copied into `Contents/Resources` automatically.
- Verify with a Release build, `plutil -p <SwiftClip.app>/Contents/Info.plist`, and `cmp -s SwiftClip/Resources/AppIcon.icns <SwiftClip.app>/Contents/Resources/AppIcon.icns`.

### Main shortcut opened the status-item menu

The `Main` global shortcut initially called `statusItem.button?.performClick(nil)`, so it opened the menu-bar dropdown instead of the standalone snippet-style popup requested by the user.

Solution:
- Keep `StatusItemController.showMenu()` for actual menu-bar icon clicks.
- Add `StatusItemController.showStandalonePopupAtCursor()` for the global shortcut path.
- Route `KeyboardShortcuts.onKeyUp(for: .mainMenu)` to `showStandalonePopupAtCursor()`.
- Build that popup through `StandalonePopupMenuBuilder`.
- Present it with `NSMenu.popUp(positioning:at:in:)` at `NSEvent.mouseLocation`, offset slightly so it appears next to the cursor.
- Preserve the root popup layout: History header, history range submenus, Snippets header, snippet folder submenus, then actions.

### Snippet editor could not reorder snippets or move them between folders

The snippet editor originally listed folders and snippets without reordering commands, so the saved `sortIndex` values could only follow creation order.

Solution:
- Added `SnippetStore` move APIs for folder ordering, same-folder snippet ordering, and cross-folder snippet moves.
- Keep all persisted folder and snippet orders normalized through `sortIndex` after every move.
- Added SwiftUI drag/drop support in `SnippetOutlineView` using `Transferable` payloads scoped to the snippet outline.
- Dropping a snippet on a folder moves it to the end of that folder; dropping on another snippet inserts it before or after the target row depending on drop position.
- Added `SnippetStoreReorderingTests` to cover folder reordering, same-folder snippet reordering, same-folder drop-to-end behavior, and cross-folder moves.

Follow-up fix:
- The custom `Transferable` payload type `app.swiftclip.snippet-outline-item` must be exported in `Resources/Info.plist`; otherwise archive builds warn that the app owns an undeclared type.
- Folder and snippet outline rows use a full-width `contentShape(Rectangle())` drop area so cross-folder snippet drops do not depend on hitting only the visible label text.

## Verification Already Completed

Debug build:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Tests:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

Result:
- `** TEST SUCCEEDED **`
- Test result bundle: `/private/tmp/swiftclip-derived/Logs/Test/Test-SwiftClip-2026.05.05_11-25-50-+0900.xcresult`

Launch:

```sh
./script/build_and_run.sh --verify
```

Result:
- Debug app launched successfully.
- Debug app path: `build/DerivedData/Build/Products/Debug/SwiftClip.app`

Shortcut popup verification:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
./script/build_and_run.sh --verify
```

Result:
- `** BUILD SUCCEEDED **`
- `** TEST SUCCEEDED **`
- The app launched successfully after the standalone popup change.
- Test result bundle: `/private/tmp/swiftclip-derived/Logs/Test/Test-SwiftClip-2026.05.05_13-04-42-+0900.xcresult`

Snippet editor drag/drop verification:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
./script/build_and_run.sh --verify
```

Result:
- `** BUILD SUCCEEDED **`
- `** TEST SUCCEEDED **`
- Debug app launched successfully and `pgrep -x SwiftClip` verified the process.
- `SnippetStoreReorderingTests` passed for folder order, snippet order, same-folder drop-to-end behavior, and cross-folder snippet movement.
- Test result bundle: `/private/tmp/swiftclip-derived/Logs/Test/Test-SwiftClip-2026.05.05_16-46-53-+0900.xcresult`

Snippet outline UTI/drop target follow-up:

```sh
plutil -lint SwiftClip/Resources/Info.plist
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Release -destination generic/platform=macOS -archivePath /private/tmp/SwiftClip-codex-archive-20260505-1703.xcarchive CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO archive
./script/build_and_run.sh --verify
```

Result:
- `Info.plist` lint passed.
- Debug build, full test suite, Release archive, and launch verification succeeded.
- The archived and Debug app `Contents/Info.plist` include `UTExportedTypeDeclarations` for `app.swiftclip.snippet-outline-item`.
- The known AppIntents metadata warning still appears; the snippet-outline UTI archive warning did not appear.

### Startup history decode and snippet drag UTI runtime warnings

The app logged `Could not load history: データのフォーマットが正しくないため、読み込むことができませんでした。` after writing history JSON with ISO-8601 dates because `HistoryStore.load()` used the default `JSONDecoder` date strategy.

The snippet editor also logged `Type "app.swiftclip.snippet-outline-item" was expected to be imported in the Info.plist of SwiftClip.app, but it was exported instead.` because the `Transferable` payload used `UTType(importedAs:)` while `Resources/Info.plist` correctly declares that app-owned type under `UTExportedTypeDeclarations`.

Solution:
- Configure `HistoryStore.load()` with `JSONDecoder.dateDecodingStrategy = .iso8601`.
- Use `UTType(exportedAs:)` for the snippet outline payload.
- Keep `testLoadDecodesPersistedISO8601Dates()` in `HistoryStoreTests` so persisted history remains loadable.

Verification:
- `plutil -lint SwiftClip/Resources/Info.plist` passed.
- `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test` passed on 2026-05-05.
- `./script/build_and_run.sh --verify` built and launched the Debug app; `pgrep -x SwiftClip` reported pid `66878`.
- A targeted unified log query for `Could not load history`, `snippet-outline-item`, `TransferableSupportError`, and `layoutSubtreeIfNeeded` returned no SwiftClip entries after launch.

Release build:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-release2 CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Result:
- `** BUILD SUCCEEDED **`
- Release app path: `/private/tmp/swiftclip-release2/Build/Products/Release/SwiftClip.app`

Release `Info.plist` was checked with `plutil` and included:
- `CFBundleIdentifier = app.swiftclip.SwiftClip`
- `CFBundleIconFile = AppIcon`
- `LSUIElement = true`
- `LSMinimumSystemVersion = 26.0`
- `NSAppleEventsUsageDescription`

## Remaining Manual Checks

- Reset SwiftClip Accessibility permission and confirm the Paste Permission window's Open Settings button opens System Settings without also showing Apple's native Accessibility Access prompt.
- Approve Accessibility permission in System Settings and verify automatic paste injection into another app.
- Exercise the menu-bar UI visually in both English and Japanese system languages.
- Copy large image/PDF payloads manually to confirm the 50 MB payload cap behavior.
- Test excluded bundle IDs by copying from an excluded app.
- Import a real user Clipy XML export if available, not only the checked-in test fixture.
- Manually assign the `Main` shortcut and confirm the standalone popup appears next to the cursor in normal use. Build and launch verification passed, but the shortcut gesture itself still needs visual confirmation with a configured shortcut.
- Manually drag a snippet from one folder to another in the snippet editor to confirm the full-width row drop target in normal pointer use.

## Design Notes For The Next Agent

- `HistoryStore`, `PreferencesStore`, and `SnippetStore` are intentionally deterministic and testable.
- SwiftData model types exist for preferences/snippets, but current persistence is file-backed JSON for implementation speed and simple verification.
- Clipboard blobs are stored separately from history metadata so large binary payloads do not bloat JSON.
- `PasteEngine` suppresses self-capture around pasteboard writes so selecting an item from the menu does not immediately duplicate it in history.
- Any future edits should preserve Swift 6 strict concurrency and keep AppKit-only APIs on the main actor.
- Do not collapse `StandalonePopupMenuBuilder` back into `MainMenuBuilder`; they intentionally represent different presentation surfaces.

### Snippet attachments

Snippets now persist `attachmentURLs` alongside text content. Dropping or selecting local files in the snippet editor stores file URLs as attachments instead of allowing TextEditor to insert absolute paths into snippet text. Selecting a snippet writes both optional `.string` text and file URL pasteboard objects, so apps that support pasted files can attach them while still receiving the prompt text.

Verification:
- `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test` passed on 2026-05-12.
- `./script/build_and_run.sh --verify` built and launched the Debug app on 2026-05-12.
- `pgrep -x SwiftClip` returned pid `29823` after launch verification.

Manual check still needed:
- Paste a mixed text/file snippet into ChatGPT or another target chat field. The pasteboard now contains file objects, but each target app decides whether pasted file URLs become uploads.

Follow-up:
- SwiftUI `TextEditor.onDrop` did not reliably prevent dropped files from being inserted as absolute path text. `SnippetDetailPane` now uses a narrow `NSViewRepresentable` text editor bridge so `NSTextView` intercepts file URL drags and stores them as snippet attachments before the text system inserts a path.

### Accessibility settings prompt duplication

The Paste Permission window's Open Settings button called `AXIsProcessTrustedWithOptions` with `"AXTrustedCheckOptionPrompt": true` and then opened the Accessibility privacy pane directly. That produced both Apple's native Accessibility Access prompt and SwiftClip's own settings route.

Solution:
- Keep launch, refresh, and paste permission checks non-prompting.
- Move the direct Accessibility settings URL into `PermissionsProbe.openAccessibilitySettings()`.
- Make the Paste Permission window's Open Settings button call only the direct settings opener.

Verification:
- `rg -n "isAccessibilityTrusted\\(prompt: true\\)|AXTrustedCheckOptionPrompt" SwiftClip` now finds only the helper's `"AXTrustedCheckOptionPrompt"` key and no `prompt: true` call sites.
- `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build` passed on 2026-05-31.
- The known non-fatal AppIntents metadata warning still appears.
