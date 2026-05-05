# SwiftClip Handoff Notes

Last updated: 2026-05-05

## Implementation Context

- The app was created from `.agent/PLANS.md` as a macOS 26+ SwiftUI/AppKit menu-bar clipboard manager.
- The primary project is `SwiftClip.xcodeproj`.
- The app uses `KeyboardShortcuts` from `https://github.com/sindresorhus/KeyboardShortcuts.git`, pinned from version `2.4.0`.
- The bundle identifier used by the generated project is `app.swiftclip.SwiftClip`.
- The app is configured as a menu-bar accessory app with `LSUIElement = true`.

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

Release build:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-release2 CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Result:
- `** BUILD SUCCEEDED **`
- Release app path: `/private/tmp/swiftclip-release2/Build/Products/Release/SwiftClip.app`

Release `Info.plist` was checked with `plutil` and included:
- `CFBundleIdentifier = app.swiftclip.SwiftClip`
- `LSUIElement = true`
- `LSMinimumSystemVersion = 26.0`
- `NSAppleEventsUsageDescription`

## Remaining Manual Checks

- Approve Accessibility permission in System Settings and verify automatic paste injection into another app.
- Exercise the menu-bar UI visually in both English and Japanese system languages.
- Copy large image/PDF payloads manually to confirm the 50 MB payload cap behavior.
- Test excluded bundle IDs by copying from an excluded app.
- Import a real user Clipy XML export if available, not only the checked-in test fixture.

## Design Notes For The Next Agent

- `HistoryStore`, `PreferencesStore`, and `SnippetStore` are intentionally deterministic and testable.
- SwiftData model types exist for preferences/snippets, but current persistence is file-backed JSON for implementation speed and simple verification.
- Clipboard blobs are stored separately from history metadata so large binary payloads do not bloat JSON.
- `PasteEngine` suppresses self-capture around pasteboard writes so selecting an item from the menu does not immediately duplicate it in history.
- Any future edits should preserve Swift 6 strict concurrency and keep AppKit-only APIs on the main actor.
