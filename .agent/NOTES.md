# SwiftClip Handoff Notes

Last updated: 2026-05-05

## Implementation Context

- The app was created from `.agent/PLANS.md` as a macOS 26+ SwiftUI/AppKit menu-bar clipboard manager.
- The primary project is `SwiftClip.xcodeproj`.
- The app uses `KeyboardShortcuts` from `https://github.com/sindresorhus/KeyboardShortcuts.git`, pinned from version `2.4.0`.
- The bundle identifier used by the generated project is `app.swiftclip.SwiftClip`.
- The app is configured as a menu-bar accessory app with `LSUIElement = true`.
- The app icon is `SwiftClip/Resources/AppIcon.icns`, referenced from `Resources/Info.plist` as `CFBundleIconFile = AppIcon`.
- The `Main` global shortcut opens a standalone History/Snippets popup next to the cursor. It intentionally does not invoke the menu-bar status item.

## Problems Encountered And Fixes

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

- Approve Accessibility permission in System Settings and verify automatic paste injection into another app.
- Exercise the menu-bar UI visually in both English and Japanese system languages.
- Copy large image/PDF payloads manually to confirm the 50 MB payload cap behavior.
- Test excluded bundle IDs by copying from an excluded app.
- Import a real user Clipy XML export if available, not only the checked-in test fixture.
- Manually assign the `Main` shortcut and confirm the standalone popup appears next to the cursor in normal use. Build and launch verification passed, but the shortcut gesture itself still needs visual confirmation with a configured shortcut.

## Design Notes For The Next Agent

- `HistoryStore`, `PreferencesStore`, and `SnippetStore` are intentionally deterministic and testable.
- SwiftData model types exist for preferences/snippets, but current persistence is file-backed JSON for implementation speed and simple verification.
- Clipboard blobs are stored separately from history metadata so large binary payloads do not bloat JSON.
- `PasteEngine` suppresses self-capture around pasteboard writes so selecting an item from the menu does not immediately duplicate it in history.
- Any future edits should preserve Swift 6 strict concurrency and keep AppKit-only APIs on the main actor.
- Do not collapse `StandalonePopupMenuBuilder` back into `MainMenuBuilder`; they intentionally represent different presentation surfaces.
