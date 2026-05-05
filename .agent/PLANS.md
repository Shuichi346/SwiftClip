
# Implementation Plan: SwiftClip — A Clipy-style Clipboard Manager for macOS Tahoe

## Overview

SwiftClip is a menu-bar-resident clipboard history manager and snippet launcher for macOS 26 Tahoe and later, optimized for Apple Silicon. After this implementation, a user can launch the app, see a clipboard icon in the macOS menu bar, copy text/files/URLs from any application and recall the last N items from a hierarchical menu, manage reusable snippets organized in folders, import/export those snippets in Clipy-compatible XML, and trigger paste behavior with global keyboard shortcuts they configure themselves.

## Stated Assumptions

These assumptions were derived from the user's answers and from research conducted during planning. Review and correct any that are wrong before handing this plan to Codex.

1. **Toolchain**: Swift 6.3, Xcode 26.4 (default install path `/Applications/Xcode.app`), deployment target macOS 26.0, architecture `arm64` only. Confirmed by Apple release notes (Xcode 26.4.1 ships Swift 6.3).
2. **Project format**: A single `SwiftClip.xcodeproj` is the primary build artifact. SwiftPM is used only to declare third-party dependencies through Xcode's "Package Dependencies" UI; there is no top-level `Package.swift`.
3. **Distribution**: Source-only release on GitHub under MIT. Users build locally in Xcode using ad-hoc signing (`-`). No notarization, no Sparkle, no Mac App Store, no GitHub Actions.
4. **Sandboxing**: App Sandbox is **disabled** (Clipy parity — global pasteboard polling, AX-based paste injection, and frontmost-app exclusion checks all require non-sandboxed entitlements).
5. **Hardened Runtime**: **Enabled** with the Accessibility/AppleEvents exceptions necessary for keystroke synthesis. App Sandbox stays off; Hardened Runtime is independent.
6. **Persistence layering**:
   - Snippets and Preferences → **SwiftData** (`ModelContainer` stored under `~/Library/Application Support/SwiftClip/Library.store`).
   - Clipboard history → **In-memory ring buffer** mirrored to a JSON index file (`History.json`) under the same Application Support directory. Large payloads (images, PDFs, RTF/RTFD) are written to a `Blobs/` subdirectory keyed by UUID; the JSON index references them by path.
7. **Deletion guarantee**: When a history item is removed (manual clear, "delete after paste", overflow eviction, or app termination cleanup), both its JSON index entry **and** its blob file under `Blobs/` are deleted in the same transaction. An orphan-blob sweep runs at startup and on every clear.
8. **History caps**: Max user-configurable limit = **50**, default = **5**. Hard ceiling for any single payload = **50 MB**; oversized clipboard contents are silently skipped.
9. **Default formats**: Plain text, RTF, RTFD, file name, and URL are enabled by default. **PDF and image are disabled by default** (user must opt in).
10. **Screenshot beta feature is removed** entirely. The renamed "拡張機能 / Extensions" tab keeps only the three modifier-triggered actions: PlainText paste, delete on select, delete after paste.
11. **Extension-tab modifier triggers**: Each action stores an arbitrary user-defined key combination (modifier flags + key code) recorded with `KeyboardShortcuts`. Default = unset (off). When unset, the action is inactive.
12. **Frontmost-app exclusion**: Resolved at the moment `NSPasteboard.changeCount` ticks, using `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. If the bundle ID matches the exclusion list, the change is dropped.
13. **Localization**: English (base) and Japanese, managed via a single `Localizable.xcstrings` catalog.
14. **Executing agent**: OpenAI Codex (single general-purpose agent). Role labels in steps are intent markers only; the same agent executes every step sequentially.
15. **Out of scope**: Sparkle auto-update, GitHub Actions CI, screenshot-history capture, Mac App Store submission, sandboxed builds, color-code preview live editing (display only), "snippet sharing" feature (placeholder only — labeled "Coming Soon" exactly as in the spec).

## Requirements

Each requirement is phrased as an observable post-condition.

1. **R1 (menu bar presence)**: After launching the built `SwiftClip.app`, a clipboard icon appears in the macOS menu bar. Clicking it opens a menu containing a `履歴 / History` section, a `スニペット / Snippets` section, and the four action items `履歴をクリア`, `スニペットを編集...`, `環境設定...`, `SwiftClipを終了`.
2. **R2 (history capture)**: Copying plain text in any application within 1 second causes a new entry to appear at the top of the History submenu, truncated to the configured character count.
3. **R3 (history recall)**: Selecting a history item from the menu places its content back on `NSPasteboard.general`. If "メニュー項目選択後に ⌘+V を入力" is on, a `Cmd+V` keystroke is synthesized into the previously frontmost application via the Accessibility API.
4. **R4 (snippet recall)**: Selecting a snippet leaf from the Snippets submenu performs the same paste flow as R3 using the snippet's stored content.
5. **R5 (snippet management)**: Opening "スニペットを編集..." shows a two-column window with a folder/snippet outline on the left and a detail editor on the right. New folders/snippets created here appear in the menu within 500 ms of the editor window closing or the data being saved.
6. **R6 (Clipy XML round-trip)**: Importing a Clipy-format XML file restores the exact folder/snippet structure shown in the user-supplied sample, preserving newlines encoded as `&#10;`. Exporting then re-importing the resulting file produces an identical in-app structure (idempotent round-trip).
7. **R7 (snippet delete confirmation)**: Pressing "削除 / Delete" on a selected snippet or folder shows the modal confirmation panel matching the attached screenshot ("スニペットを削除 / 本当に削除してもよろしいですか？" with primary "スニペットを削除" and secondary "キャンセル" buttons). No deletion happens until the user confirms.
8. **R8 (preferences persistence)**: All seven preferences-tab values survive a quit/relaunch cycle.
9. **R9 (global shortcuts)**: After assigning a shortcut for "メイン" in the Shortcuts tab and quitting/relaunching, pressing that shortcut anywhere in macOS opens the menu-bar menu at the cursor (or status-item) location.
10. **R10 (excluded apps)**: When app `com.example.PasswordVault` is in the exclusion list, copying inside that app does not add a history entry; verified by observing that `NSPasteboard.changeCount` advances but the SwiftClip history index is unchanged.
11. **R11 (ad-hoc build)**: Running `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` from the repo root produces `build/Release/SwiftClip.app` that launches without a Gatekeeper crash on the developer's machine.
12. **R12 (deletion completeness)**: After "履歴をクリア", the `Blobs/` directory under Application Support is empty (verified with `ls`), and `History.json` contains an empty array.
13. **R13 (size cap enforcement)**: Copying a 60 MB PNG does not produce a history entry; the existing history is unchanged and no file is written under `Blobs/`.
14. **R14 (default formats)**: On first launch, copying a screenshot image does **not** create a history entry until the user enables "画像" on the 対応形式 tab.
15. **R15 (localization)**: Switching the system language to Japanese and relaunching shows all UI strings in Japanese; switching to English shows them in English.

## Tech Stack and Conventions

**Language and SDK**: Swift 6.3 with strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY = complete`). Deployment target = macOS 26.0. Architectures = `arm64` only (set `EXCLUDED_ARCHS[sdk=macosx*]=x86_64`). Encoding UTF-8.

**Frameworks (Apple)**:
- `AppKit` — `NSStatusItem`, `NSMenu`, `NSMenuDelegate`, `NSPasteboard`, `NSWorkspace`, `NSAlert`, `NSOpenPanel`.
- `SwiftUI` — All windows except the menu bar dropdown.
- `SwiftData` — Snippet and preference persistence.
- `Combine` — Pasteboard polling timer and observable preferences.
- `ServiceManagement` — `SMAppService.mainApp` for "Launch at login".
- `ApplicationServices` / `CoreGraphics` — `CGEvent` keystroke synthesis and `AXIsProcessTrustedWithOptions` permission probe.
- `UniformTypeIdentifiers` — Pasteboard type filtering.

**Third-party SwiftPM dependencies** (added through Xcode → Project → Package Dependencies):
- `https://github.com/sindresorhus/KeyboardShortcuts.git` from `2.4.0`. Used for every shortcut field in the app (Shortcuts tab, Snippets tab folder shortcut, Extensions tab modifier triggers).
- No others.

**Project-level conventions**:
- File naming: `UpperCamelCase.swift`, one primary type per file.
- Folder structure under `SwiftClip/` Xcode group:
  ```
  SwiftClip/
    App/                       # SwiftClipApp, AppDelegate, lifecycle
    MenuBar/                   # NSStatusItem + NSMenu controllers
    Clipboard/                 # Pasteboard polling, history model, blob store
    Snippets/                  # SwiftData models, XML import/export
    Preferences/               # SwiftUI tab views + PreferencesStore
    SnippetEditor/             # SwiftUI two-column editor window
    Onboarding/                # First-run permission window
    Shortcuts/                 # KeyboardShortcuts.Name extensions
    Localization/              # Localizable.xcstrings
    Resources/                 # Assets.xcassets, Info.plist
    Support/                   # FileLocations, Logging, Errors
  ```
- Every persistence write to disk happens off the main actor using `Task.detached(priority: .utility)`; the SwiftData `ModelContext` is accessed via `@MainActor` for UI reads and via a dedicated `ModelActor` (`PersistenceActor`) for batch writes.
- Logging: `os.Logger` with subsystem `"app.swiftclip"` and per-module categories (`"clipboard"`, `"snippets"`, `"shortcuts"`, …). No `print`.
- Errors: every public throwing function returns a typed `enum` conforming to `Error & LocalizedError` defined in `Support/Errors.swift`.
- Comments: English only. **Do not write LLM activity-log comments** (no "added here", "fixed", "TODO from previous turn"). Comments describe what the code is, not its history.
- Imports: absolute, fully-qualified module paths; never wildcard.

**File locations on disk** (constants in `Support/FileLocations.swift`):
- App Support root: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SwiftClip", isDirectory: true)`.
- Library store: `<root>/Library.store` (SwiftData).
- History index: `<root>/History.json`.
- Blob directory: `<root>/Blobs/` — files named `<UUID>.<ext>` where `<ext>` is `txt`, `rtf`, `rtfd` (a directory), `pdf`, `png`, `tiff`, `url`, or `dat`.
- Logs: standard `os_log` console; no custom log file.

## Boundaries

```
✅ Always:
  - Follow the directory layout in "Tech Stack and Conventions".
  - Use absolute imports and the typed Error enums from Support/Errors.swift.
  - Run every blob-deleting operation through BlobStore.delete(...) so the JSON index and the file on disk stay consistent.
  - Use os.Logger (never print) and KeyboardShortcuts (never raw Carbon HotKey APIs).

⚠️ Ask First:
  - Adding any third-party SwiftPM dependency beyond KeyboardShortcuts.
  - Raising the deployment target above macOS 26.0 or below it.
  - Introducing any persistence outside FileLocations.appSupportRoot.
  - Changing the Clipy-compatible XML schema (folders > folder > snippets > snippet > {title, content}).

🚫 Never:
  - Enable App Sandbox.
  - Add Sparkle, GitHub Actions, or screenshot-history capture (explicitly out of scope).
  - Commit a developer signing identity, provisioning profile, or API token.
  - Use raw print statements, force-tries, or force-unwraps in non-test code.
  - Synthesize keystrokes without first verifying AXIsProcessTrusted == true.
  - Touch x86_64 build paths or write CUDA/MPS code (this is a pure AppKit/SwiftUI macOS app).
```

## Architecture Changes

Target tree at completion:

```
SwiftClip/                                  (repo root)
  .gitignore
  README.md
  CHANGELOG.md
  LICENSE                                   (MIT)
  SwiftClip.xcodeproj/
  SwiftClip/
    App/
      SwiftClipApp.swift                    # @main, scenes, AppDelegate hookup
      AppDelegate.swift                     # NSApplicationDelegate, lifecycle
      AppEnvironment.swift                  # DI container exposed to SwiftUI
    MenuBar/
      StatusItemController.swift            # owns NSStatusItem
      MainMenuBuilder.swift                 # NSMenu construction (NSMenuDelegate)
      HistoryMenuSection.swift              # builds the History group + range subs
      SnippetsMenuSection.swift             # builds Snippet folders + leaves
      ActionMenuSection.swift               # Clear, Edit, Preferences, Quit
    Clipboard/
      PasteboardWatcher.swift               # changeCount polling, debouncing
      ClipboardItem.swift                   # value type for one history entry
      ClipboardItemKind.swift               # enum: text/rtf/rtfd/pdf/file/url/image
      HistoryStore.swift                    # ring buffer + JSON index actor
      BlobStore.swift                       # disk read/write for large payloads
      PasteEngine.swift                     # CGEvent ⌘V + plain-text variant
    Snippets/
      SnippetFolder.swift                   # @Model
      Snippet.swift                         # @Model
      SnippetStore.swift                    # SwiftData ModelActor wrapper
      ClipyXMLCodec.swift                   # import + export (XMLParser/XMLDocument)
    Preferences/
      PreferencesWindow.swift               # SwiftUI Window with TabView
      PreferencesStore.swift                # @Observable, persisted via SwiftData
      Tabs/
        GeneralTab.swift
        MenuTab.swift
        FormatsTab.swift
        ExcludedAppsTab.swift
        ShortcutsTab.swift
        ExtensionsTab.swift                 # renamed from "ベータ機能 / Beta"
    SnippetEditor/
      SnippetEditorWindow.swift             # SwiftUI Window
      SnippetOutlineView.swift              # NSOutlineView wrapped via NSViewRepresentable
      SnippetDetailPane.swift               # right-side editor
      SnippetToolbar.swift                  # add/delete/import/export buttons
      DeleteConfirmationAlert.swift         # NSAlert wrapper matching the screenshot
    Onboarding/
      PermissionsWindow.swift               # first-run AX + Input Monitoring guide
      PermissionsProbe.swift                # AXIsProcessTrustedWithOptions wrapper
    Shortcuts/
      ShortcutNames.swift                   # KeyboardShortcuts.Name extensions
    Localization/
      Localizable.xcstrings                 # en + ja keyed by string id
    Resources/
      Assets.xcassets/
        AppIcon.appiconset/
        StatusBarIcon.imageset/             # template image, multiple sizes
      Info.plist
      SwiftClip.entitlements                # Hardened Runtime, no Sandbox
    Support/
      FileLocations.swift
      Errors.swift
      Logging.swift
      WeakBox.swift                         # tiny utility
  SwiftClipTests/
    HistoryStoreTests.swift
    BlobStoreTests.swift
    ClipyXMLCodecTests.swift
    PasteboardWatcherTests.swift
    PreferencesStoreTests.swift
    Resources/
      sample-clipy.xml                      # the user-provided fixture
```

## Agent Summary

| Agent | Step Count | Phases Involved |
|---|---|---|
| coding-agent | 24 | 1, 2, 3, 4, 5, 6, 7 |
| devops-agent | 3 | 1, 8 |
| database-agent | 2 | 2 |
| documentation-agent | 2 | 8 |
| review-agent | 8 | 1, 2, 3, 4, 5, 6, 7, 8 |

Codex executes every step sequentially. The agent labels are intent markers.

## Implementation Steps

---

### Phase 1: Project Bootstrap and Persistence Foundation

**Purpose**: After this phase, the repository contains a buildable, runnable, code-signing-`-` `SwiftClip.app` that launches, places a placeholder clipboard icon in the menu bar, and has working empty SwiftData and JSON persistence stores under `~/Library/Application Support/SwiftClip/`.

#### Step 1.1: Initialize repository skeleton
- **Agent**: devops-agent
- **Location**: repository root
- **Action**: Create `.gitignore`, `README.md`, `CHANGELOG.md`, `LICENSE`. Initialize the Xcode project at the same level.
- **Details**:
  - `.gitignore` MUST include at minimum: `.DS_Store`, `Thumbs.db`, `xcuserdata/`, `*.xcuserstate`, `DerivedData/`, `build/`, `.swiftpm/`, `Package.resolved` (kept inside the .xcodeproj package metadata only).
  - `README.md` skeleton with sections: Overview, Build Instructions (manual ad-hoc Xcode archive), Permissions Required, License (MIT). One paragraph each — content is filled by Step 8.1.
  - `CHANGELOG.md` starts with a `## [Unreleased]` heading.
  - `LICENSE` = MIT, copyright year `2026`, holder placeholder `<COPYRIGHT HOLDER>`.
  - Empty directory tracked with `.gitkeep` only if needed; the Xcode project will populate `SwiftClip/`.
- **Dependencies**: None.
- **Verification**: `git status` from the new repo root shows the four files and a clean working tree after `git add . && git commit -m "chore: bootstrap"`. Running `cat .gitignore | grep -E '^\.DS_Store$'` returns the line.
- **Complexity**: Low. **Risk**: Low.

#### Step 1.2: Create the Xcode project
- **Agent**: devops-agent
- **Location**: `SwiftClip.xcodeproj`
- **Action**: Create a macOS App Xcode project named `SwiftClip` with the directory layout from "Architecture Changes". Configure build settings.
- **Details**:
  - Template: macOS → App. Interface = SwiftUI. Language = Swift. Storage = None (we wire SwiftData manually). Tests = on (Unit, no UI).
  - Bundle ID: `app.swiftclip.SwiftClip`.
  - Build settings (`SwiftClip` target):
    - `MACOSX_DEPLOYMENT_TARGET = 26.0`
    - `SWIFT_VERSION = 6.0` (Xcode 26.4 maps this to the 6.3 compiler with the Swift 6 language mode).
    - `SWIFT_STRICT_CONCURRENCY = complete`
    - `ARCHS = arm64`
    - `EXCLUDED_ARCHS[sdk=macosx*] = x86_64`
    - `ENABLE_HARDENED_RUNTIME = YES`
    - `ENABLE_APP_SANDBOX = NO`
    - `CODE_SIGN_IDENTITY = -`
    - `CODE_SIGN_STYLE = Manual`
    - `LSUIElement = YES` in `Info.plist` (menu-bar-only, no Dock icon).
    - `LSMinimumSystemVersion = 26.0`.
    - `NSAppleEventsUsageDescription = "SwiftClip pastes into the previously focused app on your behalf when you select a history item."`
  - Create the empty Swift files referenced by the directory tree as stubs (each containing only `import Foundation` plus a placeholder `// MARK: - <name>` so the build succeeds).
  - Create `SwiftClip/Resources/SwiftClip.entitlements` with `com.apple.security.app-sandbox = false` only. No additional entitlements are required for the AX-keystroke path since AX permission is granted at the OS level, not via entitlements.
- **Dependencies**: Step 1.1.
- **Verification**: Open the project in Xcode and run `Product → Build`. Build Succeeds with 0 errors and 0 warnings. Running `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination "platform=macOS,arch=arm64" build` from the repo root prints `** BUILD SUCCEEDED **`.
- **Complexity**: Medium. **Risk**: Low.

#### Step 1.3: Wire up KeyboardShortcuts dependency
- **Agent**: devops-agent
- **Location**: `SwiftClip.xcodeproj` → Package Dependencies
- **Action**: Add `https://github.com/sindresorhus/KeyboardShortcuts.git`, version rule "Up to Next Major", starting `2.4.0`. Add `KeyboardShortcuts` library to the `SwiftClip` target's "Frameworks, Libraries, and Embedded Content".
- **Details**: After adding, `import KeyboardShortcuts` MUST compile inside any file in the `SwiftClip` target.
- **Dependencies**: Step 1.2.
- **Verification**: Add a temporary `import KeyboardShortcuts` at the top of `App/SwiftClipApp.swift`, build with `xcodebuild`, expect `BUILD SUCCEEDED`. Remove the temporary import.
- **Complexity**: Low. **Risk**: Low.

#### Step 1.4: Create FileLocations, Logging, and Errors support modules
- **Agent**: coding-agent
- **Location**: `SwiftClip/Support/`
- **Action**: Implement `FileLocations.swift`, `Logging.swift`, `Errors.swift`.
- **Details**:
  - `FileLocations.swift` exposes a `enum FileLocations` with these `static let` URLs (computed lazily from `FileManager`):
    - `appSupportRoot: URL` — creates the directory if missing.
    - `libraryStoreURL: URL` — `<root>/Library.store`.
    - `historyIndexURL: URL` — `<root>/History.json`.
    - `blobsDirectory: URL` — `<root>/Blobs/`, created on first access.
  - The directory-creation helper MUST use `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` and tolerate `EEXIST`.
  - `Logging.swift` exposes `enum Log` with `static let clipboard = Logger(subsystem: "app.swiftclip", category: "clipboard")` plus categories `snippets`, `shortcuts`, `menu`, `prefs`, `app`, `xml`.
  - `Errors.swift` defines `enum SwiftClipError: Error, LocalizedError` with cases:
    - `.persistenceFailed(underlying: Error)`
    - `.xmlParseFailed(reason: String)`
    - `.xmlExportFailed(reason: String)`
    - `.payloadTooLarge(bytes: Int)`
    - `.permissionDenied(kind: PermissionKind)` where `enum PermissionKind { case accessibility, inputMonitoring }`
    - `.shortcutConflict(name: String)`
    - `.fileMissing(path: String)`
    - Every case provides a localized `errorDescription` returning `String(localized: ...)` keys defined later in the catalog (use placeholder English strings for now).
- **Dependencies**: Step 1.2.
- **Verification**: Build succeeds. Add a one-shot unit test `FileLocationsSmokeTest` that asserts `FileManager.default.fileExists(atPath: FileLocations.blobsDirectory.path)` is true after calling `FileLocations.appSupportRoot`. Test passes.
- **Complexity**: Low. **Risk**: Low.

#### Step 1.5: Implement minimal status item with placeholder menu
- **Agent**: coding-agent
- **Location**: `SwiftClip/App/AppDelegate.swift`, `SwiftClip/MenuBar/StatusItemController.swift`
- **Action**: Implement a status item that appears on launch with a clipboard SF Symbol and shows a placeholder `NSMenu` containing only "Quit SwiftClip".
- **Details**:
  - `StatusItemController` is a `@MainActor final class`. On `init()`, it creates `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`, sets `button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "SwiftClip")?.withSymbolConfiguration(.init(scale: .medium))`, marks it as `isTemplate = true`.
  - Exposes `func attachMenu(_ menu: NSMenu)`.
  - `AppDelegate.applicationDidFinishLaunching(_:)` constructs the controller, attaches a placeholder `NSMenu` containing one item ("Quit") whose target/action calls `NSApp.terminate(nil)`.
  - `SwiftClipApp` wires the AppDelegate via `@NSApplicationDelegateAdaptor`. The body returns `Settings { EmptyView() }` (no main window).
- **Dependencies**: Step 1.4.
- **Verification**: Run the app from Xcode. A clipboard icon appears in the menu bar. Click it; the menu shows "Quit". Clicking Quit terminates the app. The Dock does not show an icon (because `LSUIElement = YES`).
- **Complexity**: Low. **Risk**: Low.

#### Step 1.G: Phase Gate — Bootstrap Verification
- **Agent**: review-agent
- **Action**: Confirm Phase 1 outputs.
- **Verification**:
  - `xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug build` ⇒ `BUILD SUCCEEDED`.
  - Launching the resulting `.app` shows the clipboard menu-bar icon.
  - `ls ~/Library/Application\ Support/SwiftClip/Blobs/` returns an empty directory after first launch (created by `FileLocations` lazy init when any test or runtime path touches it).
  - `xcodebuild test -project SwiftClip.xcodeproj -scheme SwiftClip` runs `FileLocationsSmokeTest` and reports it as passed.
- **Dependencies**: 1.1, 1.2, 1.3, 1.4, 1.5.

---

### Phase 2: Persistence Models and Stores

**Purpose**: After this phase, snippets, folders, and preferences round-trip through SwiftData; clipboard history items round-trip through `HistoryStore`+`BlobStore`; deletion guarantees pass automated tests.

#### Step 2.1: Define SwiftData models for snippets and preferences
- **Agent**: database-agent
- **Location**: `SwiftClip/Snippets/SnippetFolder.swift`, `SwiftClip/Snippets/Snippet.swift`, `SwiftClip/Preferences/PreferencesStore.swift`
- **Action**: Define three `@Model` classes.
- **Details**:
  - `final class SnippetFolder` (`@Model`):
    - `id: UUID` (`@Attribute(.unique)`)
    - `title: String`
    - `sortIndex: Int`
    - `isEnabled: Bool` (default `true`)
    - `shortcutName: String?` (key into `KeyboardShortcuts.Name` registry)
    - `@Relationship(deleteRule: .cascade, inverse: \Snippet.folder) snippets: [Snippet] = []`
  - `final class Snippet` (`@Model`):
    - `id: UUID` (`@Attribute(.unique)`)
    - `title: String`
    - `content: String`
    - `sortIndex: Int`
    - `isEnabled: Bool` (default `true`)
    - `shortcutName: String?`
    - `folder: SnippetFolder?`
  - `final class PreferencesRecord` (`@Model`) — single-row settings:
    - `id: UUID = UUID()` (`@Attribute(.unique)`)
    - All scalar settings as stored properties matching the spec verbatim. Group them in code by tab for readability:
      - General: `launchAtLogin: Bool` (default false), `pasteAfterSelect: Bool` (default true), `sendCrashLogs: Bool` (default true), `historyLimit: Int` (default 5, clamped 1...50), `historySortOrder: HistorySortOrder` (raw `String`, default `.lastUsed`), `statusBarIconStyle: StatusBarIconStyle` (default `.clipboard`).
      - Menu: `inlineHistoryCount: Int` (default 0), `folderItemCount: Int` (default 5, range 1...50), `menuTitleCharLimit: Int` (default 20), `dedupeCopy: Bool` (true), `dedupeOverwrite: Bool` (true), `prefixNumbers: Bool` (true), `numberStartZero: Bool` (false), `showItemIcons: Bool` (false), `numberKeyShortcuts: Bool` (false), `showClearMenuItem: Bool` (true), `confirmBeforeClear: Bool` (true), `showTooltips: Bool` (true), `tooltipCharLimit: Int` (default 200), `previewColorCodes: Bool` (true), `showImages: Bool` (true), `imagePreviewWidth: Int` (default 100), `imagePreviewHeight: Int` (default 32).
      - Formats: seven `Bool` flags `formatPlainText` (true), `formatRTF` (true), `formatRTFD` (true), `formatPDF` (**false** by default), `formatFileName` (true), `formatURL` (true), `formatImage` (**false** by default).
      - Excluded apps: `excludedBundleIDs: [String]` (encoded as `Codable` JSON string, since SwiftData prefers primitives — store `excludedBundleIDsRaw: String = "[]"` and add a non-stored computed accessor).
      - Extensions: `extPlainTextPasteShortcut: String?` (KeyboardShortcuts.Name id), `extDeleteOnSelectShortcut: String?`, `extDeleteAfterPasteShortcut: String?`. All default `nil` (off).
  - `enum HistorySortOrder: String, Codable, CaseIterable { case lastUsed, firstCopied }`
  - `enum StatusBarIconStyle: String, Codable, CaseIterable { case clipboard, scissors, document }`
- **Dependencies**: Step 1.G.
- **Verification**: Add `SnippetModelTests`: instantiates a `ModelContainer(for: SnippetFolder.self, Snippet.self, PreferencesRecord.self)` in-memory, inserts one folder with two snippets, fetches them back, asserts `snippets.count == 2` and that deleting the folder cascades to zero snippets. Test passes.
- **Complexity**: Medium. **Risk**: Low.

#### Step 2.2: Implement SnippetStore as a ModelActor
- **Agent**: database-agent
- **Location**: `SwiftClip/Snippets/SnippetStore.swift`
- **Action**: Wrap the SwiftData container in an actor for off-main-thread writes.
- **Details**:
  - `@ModelActor actor SnippetStore`. Public API:
    - `init(url: URL = FileLocations.libraryStoreURL) throws` — creates a `ModelContainer` rooted at the URL; the actor's auto-synthesized initializer takes a `ModelContainer`, so provide a static factory `static func make() throws -> SnippetStore`.
    - `func allFolders() throws -> [SnippetSummary]` returning a Sendable snapshot struct `struct SnippetSummary: Sendable, Identifiable { let id: UUID; let title: String; let isEnabled: Bool; let shortcutName: String?; let snippets: [SnippetLeaf] }` and `struct SnippetLeaf: Sendable, Identifiable { let id: UUID; let title: String; let content: String; let isEnabled: Bool; let shortcutName: String? }`. Order by `sortIndex` ascending.
    - `func addFolder(title: String) throws -> UUID`
    - `func renameFolder(id: UUID, to title: String) throws`
    - `func deleteFolder(id: UUID) throws`
    - `func addSnippet(folderID: UUID, title: String, content: String) throws -> UUID`
    - `func updateSnippet(id: UUID, title: String?, content: String?, isEnabled: Bool?, shortcutName: String?) throws`
    - `func deleteSnippet(id: UUID) throws`
    - `func reorder(folderIDsInOrder: [UUID]) throws`
    - `func reorderSnippets(inFolder folderID: UUID, snippetIDsInOrder: [UUID]) throws`
    - `func replaceAll(with folders: [SnippetSummary]) throws` — used by XML import.
  - Every mutation calls `modelContext.save()` and re-throws as `SwiftClipError.persistenceFailed`.
- **Dependencies**: Step 2.1.
- **Verification**: `SnippetStoreTests` exercises add/rename/delete and `replaceAll`. After replaceAll with two folders × three snippets, `allFolders()` returns the same structure. Test passes.
- **Complexity**: Medium. **Risk**: Low.

#### Step 2.3: Implement BlobStore for large clipboard payloads
- **Agent**: coding-agent
- **Location**: `SwiftClip/Clipboard/BlobStore.swift`
- **Action**: Disk-backed store keyed by UUID with sweep + delete guarantees.
- **Details**:
  - `actor BlobStore` with these methods:
    - `func write(_ data: Data, ext: String) throws -> URL` — writes atomically to `<blobsDir>/<UUID>.<ext>`, returns URL.
    - `func writeDirectory(from sourceURL: URL, ext: String) throws -> URL` — for RTFD packages; copies recursively.
    - `func read(url: URL) throws -> Data`
    - `func delete(url: URL)` — best-effort; logs on failure but never throws.
    - `func deleteAll()` — removes everything under `Blobs/`.
    - `func sweep(referencedURLs: Set<URL>)` — deletes any file in `Blobs/` whose URL is not in the referenced set. Called at startup and after `deleteAll`.
  - Size cap: callers MUST check `data.count <= 50 * 1024 * 1024` before invoking `write`. `write` re-asserts and throws `.payloadTooLarge` if violated.
- **Dependencies**: Step 1.4.
- **Verification**: `BlobStoreTests`: write 5 small blobs, verify all 5 files exist, call `sweep(referencedURLs: [first 2])`, verify only 2 remain on disk. `deleteAll` leaves the directory empty (`contentsOfDirectory` returns `[]`). Test passes.
- **Complexity**: Medium. **Risk**: Medium — file-system races during sweep.
- **Idempotence & Recovery**: Yes. `write` uses atomic `.atomic` flag (rename-on-write). `sweep` ignores files added during iteration by re-listing. If `sweep` partially fails, re-running it converges. `deleteAll` is idempotent.

#### Step 2.4: Implement HistoryStore (in-memory + JSON index)
- **Agent**: coding-agent
- **Location**: `SwiftClip/Clipboard/HistoryStore.swift`, `SwiftClip/Clipboard/ClipboardItem.swift`, `SwiftClip/Clipboard/ClipboardItemKind.swift`
- **Action**: Ring buffer with persistent JSON index, integrating BlobStore.
- **Details**:
  - `enum ClipboardItemKind: String, Codable, CaseIterable { case plainText, rtf, rtfd, pdf, fileName, url, image }`
  - `struct ClipboardItem: Identifiable, Codable, Sendable, Equatable`:
    - `id: UUID`
    - `kind: ClipboardItemKind`
    - `createdAt: Date`
    - `lastUsedAt: Date`
    - `previewText: String` — short representation for menus (≤ 1024 chars stored).
    - `inlineText: String?` — full text for kinds `plainText`, `url`, `fileName` (kept in memory + JSON).
    - `blobURL: URL?` — set for `rtf`, `rtfd`, `pdf`, `image`. `nil` for inline kinds.
    - `byteSize: Int`
    - `sourceBundleID: String?`
  - `actor HistoryStore`:
    - `private(set) var items: [ClipboardItem]` — newest first.
    - `init(blobStore: BlobStore)` — loads `History.json` if present; on parse failure, logs and starts empty. Then calls `blobStore.sweep(referencedURLs: itemBlobURLs)`.
    - `func insert(_ item: ClipboardItem, limit: Int, dedupePolicy: DedupePolicy)` where `enum DedupePolicy { case none, skipDuplicate, moveToFront }`. After insert, evict overflow tail; for each evicted item with a non-nil `blobURL`, call `blobStore.delete(url:)`.
    - `func clearAll()` — empties `items`, awaits `blobStore.deleteAll()`, persists empty JSON.
    - `func remove(id: UUID)` — same blob-cleanup contract.
    - `func touch(id: UUID)` — updates `lastUsedAt`, optionally moves to front.
    - `private func persist()` — encodes `items` to `History.json` atomically. Called after every mutation. Encodes via `JSONEncoder` with `.iso8601` dates and sorted keys.
- **Dependencies**: Step 2.3.
- **Verification**: `HistoryStoreTests`:
  - Insert 7 items with `limit = 5`. Assert `items.count == 5` and the 2 oldest are gone.
  - Insert two items with blobs, then call `clearAll()`. Assert blobs directory is empty AND `History.json` decodes to `[]`.
  - Insert duplicate plain-text item with policy `.skipDuplicate` — count unchanged.
  - Insert duplicate with `.moveToFront` — count unchanged but the item is at index 0.
  All tests pass.
- **Complexity**: Medium. **Risk**: Medium — concurrency between actor mutations and JSON persistence.
- **Idempotence & Recovery**: Yes. JSON write uses `Data.write(to:options:.atomic)`. If a partial write crashes, the previous file remains. `clearAll` is idempotent (empty → empty). On startup, `sweep` reconciles disk state with in-memory items.

#### Step 2.G: Phase Gate — Persistence Verification
- **Agent**: review-agent
- **Action**: Run all unit tests; inspect on-disk state.
- **Verification**:
  - `xcodebuild test -project SwiftClip.xcodeproj -scheme SwiftClip` reports all tests in `HistoryStoreTests`, `BlobStoreTests`, `SnippetStoreTests`, `SnippetModelTests` as passed.
  - Manual: launch app, run a small in-app smoke (a debug menu item that inserts one synthetic image item, then "Clear" — verified by `ls Blobs/` returning empty and `cat History.json` returning `[]`). Remove the debug menu item before phase 3.
- **Dependencies**: 2.1, 2.2, 2.3, 2.4.

---

### Phase 3: Pasteboard Watching, Paste Engine, and Permissions

**Purpose**: After this phase, copying in any application produces a history entry within 1 second; selecting a history item via a temporary debug menu places it back on the pasteboard and (with permission) synthesizes ⌘V into the previous app. The exclusion list is enforced.

#### Step 3.1: Permissions probe
- **Agent**: coding-agent
- **Location**: `SwiftClip/Onboarding/PermissionsProbe.swift`
- **Action**: Wrap `AXIsProcessTrustedWithOptions` and Input Monitoring detection.
- **Details**:
  - `enum PermissionsProbe`:
    - `static func isAccessibilityTrusted(prompt: Bool) -> Bool` — calls `AXIsProcessTrustedWithOptions` with the `kAXTrustedCheckOptionPrompt` key when `prompt = true`.
    - `static func openAccessibilityPane()` — opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
    - Input Monitoring is not strictly required for AX-keystroke synthesis, but the onboarding window references it. Add `static func openInputMonitoringPane()` opening the corresponding URL.
  - These functions are pure and synchronous; no state.
- **Dependencies**: Step 1.G.
- **Verification**: Build succeeds; `PermissionsProbe.isAccessibilityTrusted(prompt: false)` returns a `Bool` without crashing in tests.
- **Complexity**: Low. **Risk**: Low.

#### Step 3.2: Pasteboard watcher
- **Agent**: coding-agent
- **Location**: `SwiftClip/Clipboard/PasteboardWatcher.swift`
- **Action**: Poll `NSPasteboard.general.changeCount` and emit new `ClipboardItem`s.
- **Details**:
  - `final class PasteboardWatcher: @unchecked Sendable`.
  - Init parameters: `pasteboard: NSPasteboard = .general`, `pollInterval: TimeInterval = 0.5`, `enabledKindsProvider: @MainActor () -> Set<ClipboardItemKind>`, `excludedBundleIDsProvider: @MainActor () -> Set<String>`, `historyStore: HistoryStore`, `blobStore: BlobStore`, `historyLimitProvider: @MainActor () -> Int`, `dedupePolicyProvider: @MainActor () -> DedupePolicy`.
  - Starts a `Timer.scheduledTimer` on `RunLoop.main` (.common modes). On each tick:
    1. Read current `changeCount`. If equal to last seen, return.
    2. Capture `frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. If in exclusion set, update `lastChangeCount` and return without recording.
    3. Determine the highest-priority enabled type present on the pasteboard, in this order: `image` (`.tiff`/`.png`), `pdf` (`com.adobe.pdf`), `rtfd` (`com.apple.flat-rtfd` / package), `rtf` (`public.rtf`), `fileName` (`public.file-url`), `url` (`public.url`), `plainText` (`public.utf8-plain-text`).
    4. Skip if the resolved kind is not in `enabledKindsProvider()`.
    5. Read raw bytes. If `byteSize > 50 * 1024 * 1024`, log and skip.
    6. Build `ClipboardItem`. For inline kinds, fill `inlineText` (truncated to 1 MiB of UTF-8) and leave `blobURL` nil. For blob kinds, write to `BlobStore` first.
    7. Compute `previewText` ≤ 1024 chars: for text kinds = first 1024 chars; for image = `String(localized: "[Image \(width)×\(height)]")`; for pdf = `String(localized: "[PDF \(formattedSize)]")`; for fileName = the path basename; for rtfd = first 1024 chars of plain-text fallback.
    8. Call `await historyStore.insert(item, limit: historyLimitProvider(), dedupePolicy: dedupePolicyProvider())`.
  - All cross-actor calls hop appropriately. Closure providers are `@MainActor` because they read `PreferencesStore`.
- **Dependencies**: Step 2.4, Step 3.1.
- **Verification**: `PasteboardWatcherTests` uses an in-memory `NSPasteboard(name: .init("test"))`, writes a string, ticks the watcher manually, asserts a new item is in `historyStore.items` with `previewText` matching. Asserts that an excluded bundle ID prevents the insert. Asserts that a 60 MB synthetic blob is skipped. Tests pass.
- **Complexity**: High. **Risk**: Medium — UTI detection edge cases.
- **Idempotence & Recovery**: N/A (no destructive action).

#### Step 3.3: Paste engine
- **Agent**: coding-agent
- **Location**: `SwiftClip/Clipboard/PasteEngine.swift`
- **Action**: Restore content to pasteboard and synthesize ⌘V.
- **Details**:
  - `enum PasteEngine`:
    - `static func restore(_ item: ClipboardItem, blobStore: BlobStore, asPlainText: Bool) async throws` — clears `NSPasteboard.general`, writes the appropriate type. If `asPlainText` is true and the item is `rtf`/`rtfd`/`fileName`/`url`, write only `public.utf8-plain-text` derived from `previewText` or full inline text.
    - `static func sendCommandV()` — synthesizes key down + up for ⌘V using `CGEvent`. MUST verify `PermissionsProbe.isAccessibilityTrusted(prompt: false)` first; if false, throw `.permissionDenied(.accessibility)`.
    - `static func paste(_ item: ClipboardItem, blobStore: BlobStore, asPlainText: Bool) async throws` — calls `restore` then, after a 30 ms delay (`try await Task.sleep(for: .milliseconds(30))`), `sendCommandV`.
- **Dependencies**: Step 3.1, Step 2.3.
- **Verification**: Manual: with the app running and AX permission granted, copy text into the app's history, focus TextEdit, click the history item — the text appears in TextEdit. Without AX permission granted, the call throws `.permissionDenied` and SwiftUI shows an alert (added in Step 4.x). Confirm by toggling System Settings → Privacy → Accessibility for SwiftClip off.
- **Complexity**: Medium. **Risk**: High — keystroke synthesis behavior on Tahoe.
- **Idempotence & Recovery**: N/A.

#### Step 3.4: Onboarding window
- **Agent**: coding-agent
- **Location**: `SwiftClip/Onboarding/PermissionsWindow.swift`
- **Action**: SwiftUI window shown on first launch (and re-shown from a Preferences button) explaining required permissions.
- **Details**:
  - `struct PermissionsWindow: Scene` registered in `SwiftClipApp`. Shown when `UserDefaults.standard.bool(forKey: "com.swiftclip.didCompleteOnboarding") == false`.
  - Content: app icon, two cards:
    1. "Accessibility" — explanation, `Open System Settings` button calling `PermissionsProbe.openAccessibilityPane()`, live-updated checkmark when `isAccessibilityTrusted(prompt:false)` becomes true.
    2. "Input Monitoring (optional)" — same pattern.
  - Bottom button "Continue" sets the UserDefaults key to `true` and closes the window.
  - The window also sets `NSApp.activate(ignoringOtherApps: true)` on appear.
- **Dependencies**: Step 3.1.
- **Verification**: Delete the UserDefaults key, launch the app, the window appears. After clicking Continue, relaunching does not show it again.
- **Complexity**: Medium. **Risk**: Low.

#### Step 3.G: Phase Gate — Capture and Paste
- **Agent**: review-agent
- **Action**: End-to-end smoke.
- **Verification**:
  - With the app running, copy "hello" in TextEdit. Within 1 second the app's debug menu (added temporarily) lists "hello" at index 0.
  - Click the entry. ⌘V is synthesized into TextEdit; "hello" pastes.
  - Add `com.apple.TextEdit` to a hard-coded test exclusion list; copy "blocked"; verify the item does not appear.
  - All Phase 3 unit tests pass.
- **Dependencies**: 3.1, 3.2, 3.3, 3.4.

---

### Phase 4: Menu-Bar UI

**Purpose**: After this phase, the menu bar dropdown matches the screenshot — History grouped into ranges, Snippets folders with submenus, action items at the bottom, all driven by live data. Selecting any leaf invokes the paste flow.

#### Step 4.1: Menu section builders
- **Agent**: coding-agent
- **Location**: `SwiftClip/MenuBar/HistoryMenuSection.swift`, `SwiftClip/MenuBar/SnippetsMenuSection.swift`, `SwiftClip/MenuBar/ActionMenuSection.swift`
- **Action**: Each builder returns `[NSMenuItem]` from a snapshot.
- **Details**:
  - `HistoryMenuSection.build(items: [ClipboardItem], prefs: PreferencesSnapshot) -> [NSMenuItem]`:
    - Adds a disabled header item with title `String(localized: "menubar.history.header")` ("履歴" / "History").
    - First `prefs.inlineHistoryCount` items appear inline. Their titles use `formatTitle(item, prefs)` — see below.
    - Remaining items grouped into chunks of `prefs.folderItemCount` per submenu. Submenu title = `"\(rangeStart) - \(rangeEnd)"`. Submenu lazily populated via `NSMenuDelegate.menuNeedsUpdate(_:)`.
    - Title formatting:
      - If `prefs.prefixNumbers`, prefix `"\(index). "` (or `"0. "` if `numberStartZero`).
      - Truncate `previewText` to `prefs.menuTitleCharLimit` characters with ellipsis.
      - If `prefs.numberKeyShortcuts` and the inline index ∈ 1...9, set `keyEquivalent` to that digit, no modifier.
      - Set `toolTip` to `previewText` truncated to `prefs.tooltipCharLimit` if `prefs.showTooltips`.
      - For `kind == .image` with `prefs.showImages`, set `image` to the thumbnail (loaded from blob, scaled to `prefs.imagePreviewWidth × prefs.imagePreviewHeight`).
      - For text matching `^#[0-9A-Fa-f]{6}$` and `prefs.previewColorCodes`, set `image` to a 16×16 `NSImage` filled with that color.
    - Each item's target/action invokes a closure stored in `representedObject` — the menu controller resolves to `PasteEngine.paste(...)`.
  - `SnippetsMenuSection.build(folders: [SnippetSummary], prefs: PreferencesSnapshot) -> [NSMenuItem]`:
    - Header item "スニペット / Snippets".
    - One submenu per folder; folder children = enabled snippets in `sortIndex` order.
    - Skip disabled folders/snippets entirely.
  - `ActionMenuSection.build(prefs: PreferencesSnapshot) -> [NSMenuItem]`:
    - "履歴をクリア" — only included if `prefs.showClearMenuItem`. If `prefs.confirmBeforeClear`, the action shows an `NSAlert` first.
    - "スニペットを編集..."
    - "環境設定..." (`,` keyEquivalent with `.command`)
    - "SwiftClipを終了" (`q` keyEquivalent with `.command`)
- **Dependencies**: Step 2.4, Step 2.2, Step 3.3.
- **Verification**: `MenuBuilderTests` constructs synthetic snapshots and asserts the resulting `NSMenuItem` titles, tooltips, and key equivalents match expected values. Tests pass.
- **Complexity**: High. **Risk**: Medium — submenu lazy population edge cases.
- **Idempotence & Recovery**: N/A.

#### Step 4.2: MainMenuBuilder and StatusItemController integration
- **Agent**: coding-agent
- **Location**: `SwiftClip/MenuBar/MainMenuBuilder.swift`, update `StatusItemController.swift`
- **Action**: Compose sections, set the menu on the status item, refresh when underlying state changes.
- **Details**:
  - `final class MainMenuBuilder: NSObject, NSMenuDelegate, @MainActor`. Holds weak references to `HistoryStore`, `SnippetStore`, `PreferencesStore`, `BlobStore`.
  - `func currentMenu() -> NSMenu` rebuilds the entire menu using the section builders and the latest snapshot. Sets `self` as `delegate` for lazy submenus.
  - `menuWillOpen(_:)` triggers an awaited refresh of history+snippet snapshots before the user sees the menu.
  - Subscribes to `PreferencesStore` `@Observable` changes and to `HistoryStore`'s notification stream (introduce `AsyncStream<Void>` in `HistoryStore` emitted after every mutation) so that an open menu rebuilds reactively. Closed menus do not need to be rebuilt eagerly — `menuWillOpen` is sufficient.
- **Dependencies**: Step 4.1.
- **Verification**: Run app. Copy 10 items in TextEdit. Open the menu — first 5 items appear under "1 - 5" (or inline if `inlineHistoryCount > 0`). Title format honors current preferences. Snippets section is empty (no snippets yet). Selecting any history entry pastes it into the previously focused window.
- **Complexity**: Medium. **Risk**: Low.

#### Step 4.G: Phase Gate — Menu-Bar UI
- **Agent**: review-agent
- **Action**: Visual confirmation against the user-supplied screenshot.
- **Verification**:
  - Open the menu. Layout matches the first attached screenshot: header "履歴", inline range "1 - 5" with a submenu chevron, "スニペット" header, action items at the bottom in the listed order. Confirm in both English and Japanese (toggle system locale).
  - Selecting an action item performs its action.
- **Dependencies**: 4.1, 4.2.

---

### Phase 5: Preferences Window (7 tabs)

**Purpose**: After this phase, every preference described in the spec is editable, persists across launches, and the live menu reflects changes within 500 ms.

#### Step 5.1: PreferencesStore wrapper
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/PreferencesStore.swift` (extend Step 2.1 model)
- **Action**: Add an `@Observable @MainActor final class PreferencesStore` that wraps the singleton `PreferencesRecord`.
- **Details**:
  - On init, fetch the single `PreferencesRecord` (create if missing).
  - Each tab binds to properties via SwiftUI bindings. Setters update the record and call `modelContext.save()` debounced at 250 ms.
  - Provides `func snapshot() -> PreferencesSnapshot` — a Sendable struct used by menu builders.
  - Exposes special accessors for `excludedBundleIDs: [String]` (codes to/from the JSON-encoded backing column).
- **Dependencies**: Step 2.1.
- **Verification**: Mutate `historyLimit`, quit, relaunch — the new value is loaded.
- **Complexity**: Medium. **Risk**: Low.

#### Step 5.2: PreferencesWindow shell with toolbar tabs
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/PreferencesWindow.swift`
- **Action**: SwiftUI Window with a custom toolbar of 7 icon-buttons mirroring the screenshots.
- **Details**:
  - `Window` with `defaultSize(width: 480, height: 360)`, fixed size.
  - Tabs in order: 一般 / メニュー / 対応形式 / 除外アプリ / ショートカット / アップデート / 拡張機能.
  - **アップデート tab content**: a single label `String(localized: "prefs.updates.body")` = "Check for updates manually on GitHub: https://github.com/<owner>/SwiftClip/releases" with a clickable link button that opens the URL via `NSWorkspace.shared.open`. No auto-update logic.
  - Selected tab tracked by `@State private var selectedTab: PreferencesTab`. Toolbar uses SF Symbols matching the screenshots: `switch.2`, `list.bullet`, `doc`, `nosign`, `command`, `arrow.triangle.2.circlepath`, `sparkles` (a placeholder for "拡張機能"; verify rendering and adjust if needed).
- **Dependencies**: Step 5.1.
- **Verification**: Open the window from the menu. All 7 tabs are clickable and switch content.
- **Complexity**: Medium. **Risk**: Low.

#### Step 5.3: 一般 tab
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/GeneralTab.swift`
- **Action**: Implement controls per the spec section 2-1.
- **Details**:
  - "ログイン時に起動" — `Toggle` bound to `prefs.launchAtLogin`. When toggled true, call `try? SMAppService.mainApp.register()`; when false, `try? SMAppService.mainApp.unregister()`.
  - "メニュー項目選択後に ⌘+V を入力" — `Toggle` bound to `prefs.pasteAfterSelect`.
  - "クラッシュレポートやエラーログを送信する" — `Toggle` bound to `prefs.sendCrashLogs`. (No actual telemetry pipeline; logged only.)
  - "記憶する履歴の数" — `Stepper` 1...50 bound to `prefs.historyLimit`. Default 5.
  - "履歴のソート順" — `Picker` with two options: "最終使用日 / Last used", "コピー順 / First copied".
  - "ステータスバー・アイコン" — `Picker` with three options matching `StatusBarIconStyle`. Selecting a value updates `StatusItemController.button.image`.
- **Dependencies**: Step 5.2.
- **Verification**: Toggle launch-at-login; run `launchctl print gui/$UID/app.swiftclip.SwiftClip` and observe the registration entry. Change history limit to 10, copy 12 items, verify menu shows 10 newest. Change icon to "scissors" — menu-bar icon updates.
- **Complexity**: Medium. **Risk**: Low.

#### Step 5.4: メニュー tab
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/MenuTab.swift`
- **Action**: Numeric fields and toggles per spec section 2-2.
- **Details**: Each control binds directly to the corresponding `PreferencesRecord` property. Dependent toggles (e.g., "重複した履歴を上書きする" depends on "重複した履歴をコピーする") are disabled (`.disabled`) when the parent is off. Numeric fields use `TextField` with `Int` formatter and clamp to sane ranges (0...50 for inline count, 1...50 for folder count, 1...200 for char limits, 1...1024 for tooltip char limit, 16...512 for image preview dimensions).
- **Dependencies**: Step 5.2.
- **Verification**: Set "メニューに表示する文字数" = 5. Copy "abcdefghij". Menu shows "abcde…". Toggle "メニュー項目の先頭に数字を付加" off — numbers disappear.
- **Complexity**: Medium. **Risk**: Low.

#### Step 5.5: 対応形式 tab
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/FormatsTab.swift`
- **Action**: Seven toggles. Defaults: text/RTF/RTFD/fileName/URL = on; PDF/image = off.
- **Details**: Each toggle binds to the corresponding `formatXxx` property. The watcher's `enabledKindsProvider` reads these flags.
- **Dependencies**: Step 5.2.
- **Verification**: With "画像" off (default), copy a screenshot — no entry appears. Turn it on — copy again, the entry appears with a thumbnail.
- **Complexity**: Low. **Risk**: Low.

#### Step 5.6: 除外アプリ tab
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/ExcludedAppsTab.swift`
- **Action**: List view of bundle IDs with + and − buttons.
- **Details**:
  - List rows show app icon (`NSWorkspace.shared.icon(forFile: appURL.path)`), display name, bundle ID. Striped row backgrounds via `.alternatingRowBackgrounds()`.
  - "+" presents `NSOpenPanel` constrained to `.application` UTType under `/Applications`. On selection, derive bundle ID from `Bundle(url:)?.bundleIdentifier`, append to `prefs.excludedBundleIDs` (deduplicated).
  - "−" removes the selected row.
- **Dependencies**: Step 5.2.
- **Verification**: Add Safari from Applications. Copy text in Safari — no entry appears in history. Remove Safari — copying again does add entries.
- **Complexity**: Medium. **Risk**: Low.

#### Step 5.7: ショートカット tab
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/ShortcutsTab.swift`, `SwiftClip/Shortcuts/ShortcutNames.swift`
- **Action**: Bind four `KeyboardShortcuts.Recorder` views.
- **Details**:
  - `ShortcutNames.swift`:
    ```swift
    extension KeyboardShortcuts.Name {
        static let openMainMenu = Self("openMainMenu")
        static let openHistorySubmenu = Self("openHistorySubmenu")
        static let openSnippetsSubmenu = Self("openSnippetsSubmenu")
        static let clearHistory = Self("clearHistory")
        static let extPlainTextPaste = Self("extPlainTextPaste")
        static let extDeleteOnSelect = Self("extDeleteOnSelect")
        static let extDeleteAfterPaste = Self("extDeleteAfterPaste")
    }
    ```
    Per-folder and per-snippet shortcuts use dynamic names: `Self("folder.\(uuid)")` / `Self("snippet.\(uuid)")`.
  - On app start, register handlers via `KeyboardShortcuts.onKeyDown(for:)` for each fixed name.
  - "メイン" handler: programmatically pop up the status item menu via `statusItem.button?.performClick(nil)`.
  - "履歴" handler: pop up the menu and immediately highlight the History submenu (use `NSMenu.popUp(positioning:at:in:)` on the submenu directly under the status item button frame).
  - "スニペット" handler: same as above for the Snippets submenu.
  - "履歴をクリア" handler: invoke the same clear flow as the menu item.
- **Dependencies**: Step 1.3, Step 4.2.
- **Verification**: Assign ⌥⌘V to "メイン", quit, relaunch, press ⌥⌘V → menu opens at the status item. Assign ⇧⌘⌫ to "履歴をクリア" → pressing it clears history (with confirmation if enabled).
- **Complexity**: Medium. **Risk**: Medium — focus stealing for menu popup on Tahoe.
- **Idempotence & Recovery**: N/A.

#### Step 5.8: 拡張機能 tab (formerly ベータ機能)
- **Agent**: coding-agent
- **Location**: `SwiftClip/Preferences/Tabs/ExtensionsTab.swift`
- **Action**: Three rows, each a `Toggle` plus a `KeyboardShortcuts.Recorder`. Default all unset and toggles off.
- **Details**:
  - Header note: `String(localized: "prefs.extensions.note")` = "Extensions may not preserve their settings across upgrades."
  - Row layout: `[Toggle][label][spacer][Recorder][clear-X button]`. The recorder is disabled when the toggle is off.
  - Three rows:
    1. "PlainTextとしてペースト / Paste as plain text" — when its shortcut is held during the menu selection, `PasteEngine.paste(_:asPlainText:true)`.
    2. "履歴を削除する / Delete on select" — when held during menu selection, the item is removed from history without pasting.
    3. "ペーストした後に履歴を削除する / Delete after paste" — paste normally, then remove the entry.
  - Implementation note: Modifier-held detection uses `NSEvent.modifierFlags` at the moment the menu item is invoked. The recorded `KeyboardShortcuts.Shortcut` is decomposed into `(modifierFlags, keyCode)`; when only modifiers are recorded (no key), the keyCode is `nil` and we match modifiers only. Allow modifier-only recording by accepting `KeyboardShortcuts.Recorder` shortcuts where `.key == nil`.
- **Dependencies**: Step 5.7.
- **Verification**: Record `⌥` (modifier-only) for "PlainTextとしてペースト". Hold ⌥ and select an RTF history item — the pasted content has no formatting. Without holding ⌥ — formatting is preserved.
- **Complexity**: Medium. **Risk**: Medium — KeyboardShortcuts library may not natively support modifier-only recording; if not, fall back to a custom `NSView` recorder for these three fields. Verify during implementation; if a fallback is needed, isolate it in `ExtensionsTab.swift` and document in the Decision Log.
- **Idempotence & Recovery**: N/A.

#### Step 5.G: Phase Gate — Preferences
- **Agent**: review-agent
- **Action**: Open every tab, change every control, verify persistence.
- **Verification**:
  - Quit and relaunch after editing one value per tab. All values are restored.
  - The menu reflects the updated preferences on its next open.
  - The アップデート tab opens the GitHub releases URL in the default browser.
- **Dependencies**: 5.1–5.8.

---

### Phase 6: Snippet Editor and Clipy XML Round-Trip

**Purpose**: After this phase, the snippet editor matches the attached screenshot, supports add/rename/delete/reorder of folders and snippets with confirmation dialogs, and imports/exports the exact XML schema in the user-supplied sample.

#### Step 6.1: Clipy XML codec
- **Agent**: coding-agent
- **Location**: `SwiftClip/Snippets/ClipyXMLCodec.swift`
- **Action**: Read and write the Clipy XML schema.
- **Details**:
  - Schema (verbatim from the user sample):
    ```xml
    <?xml version="1.0" encoding="utf-8" standalone="no"?>
    <folders>
      <folder>
        <title>...</title>
        <snippets>
          <snippet>
            <title>...</title>
            <content>...</content>
          </snippet>
        </snippets>
      </folder>
    </folders>
    ```
  - Newlines inside `<content>` are encoded as `&#10;` (numeric character reference) on export; `XMLParser` decodes them automatically on import.
  - Public API:
    - `enum ClipyXMLCodec`
    - `static func decode(data: Data) throws -> [SnippetSummary]` — uses `XMLParser` (SAX). On malformed XML, throws `.xmlParseFailed`. Empty `<folders/>` is valid and returns `[]`. Order preserved as document order; assigned `sortIndex` accordingly.
    - `static func encode(folders: [SnippetSummary]) throws -> Data` — uses `XMLDocument` to construct the tree, sets `version = "1.0"` and `characterEncoding = "utf-8"`, sets `isStandalone = false`. After serializing with `XMLNode.Options.nodePrettyPrint | .nodeUseDoubleQuotes`, post-process to replace literal `\n` characters inside `<content>` text nodes with `&#10;`. Output uses tab indentation (`\t`) to match the user sample exactly.
    - The post-processing step is required because `XMLDocument` does not emit `&#10;` for newlines by default — it emits literal newline characters.
  - Round-trip property: `decode(encode(x)) == x` (compared by title/content, ignoring assigned UUIDs).
- **Dependencies**: Step 2.2.
- **Verification**: `ClipyXMLCodecTests` includes:
  - `sample-clipy.xml` test fixture (the user-supplied content). `decode` returns 2 folders ("NotebookLM", "使い方色々") with correct snippet counts (2, 1) and verbatim content (newlines preserved).
  - `encode` of the decoded structure produces a byte-for-byte match with the fixture (after normalizing trailing whitespace).
  - Round-trip test passes.
- **Complexity**: High. **Risk**: Medium — exact byte-level match requires careful whitespace handling.
- **Idempotence & Recovery**: N/A.

#### Step 6.2: Snippet editor window scaffolding
- **Agent**: coding-agent
- **Location**: `SwiftClip/SnippetEditor/SnippetEditorWindow.swift`, `SnippetToolbar.swift`
- **Action**: SwiftUI window titled "SwiftClip - スニペット編集" with toolbar and split view.
- **Details**:
  - `Window("SwiftClip - \(String(localized: "editor.title"))", id: "snippet-editor")`. Default size 768×500.
  - Toolbar buttons (left to right) with SF Symbols and labels: スニペット追加 (`note.text.badge.plus`), フォルダ追加 (`folder.badge.plus`), 削除 (`minus.circle`), 有効/無効 (`switch.2`), インポート (`square.and.arrow.down`), エクスポート (`square.and.arrow.up`).
  - Body uses `NavigationSplitView` (sidebar + detail).
  - The window is opened from the menu item "スニペットを編集...".
- **Dependencies**: Step 4.2.
- **Verification**: Click the menu item; the window opens with the correct title and an empty sidebar.
- **Complexity**: Medium. **Risk**: Low.

#### Step 6.3: Outline view (left pane)
- **Agent**: coding-agent
- **Location**: `SwiftClip/SnippetEditor/SnippetOutlineView.swift`
- **Action**: Hierarchical list of folders → snippets with selection, drag-reorder, and inline rename.
- **Details**:
  - Use SwiftUI `List` with `OutlineGroup` over a tree of `SidebarNode` (`enum SidebarNode { case folder(SnippetSummary); case snippet(SnippetLeaf) }`).
  - Selection bound to a single `SidebarNode.ID`.
  - Drag-and-drop: implement `.dropDestination(for: SidebarNode.ID.self)` to move snippets between folders. Reordering within the same parent updates `sortIndex` via `SnippetStore.reorder...`.
  - Inline rename on double-click → swap the `Text` for a `TextField`; commit on Enter, cancel on Escape.
- **Dependencies**: Step 6.2, Step 2.2.
- **Verification**: Add 2 folders and 3 snippets via the toolbar (Step 6.5). Drag snippet A from folder 1 to folder 2; verify in the menu the snippet now appears under folder 2 after refresh.
- **Complexity**: High. **Risk**: Medium — SwiftUI drag-drop reorder.
- **Idempotence & Recovery**: N/A.

#### Step 6.4: Detail pane (right side)
- **Agent**: coding-agent
- **Location**: `SwiftClip/SnippetEditor/SnippetDetailPane.swift`
- **Action**: Switches between folder editor, snippet editor, and empty state.
- **Details**:
  - **Empty state**: instructional text "Select a folder or snippet to edit it."
  - **Folder selected**: large folder icon + `Text(folder.title)`, label "ショートカット", a `KeyboardShortcuts.Recorder` bound to `KeyboardShortcuts.Name("folder.\(folder.id)")`, then a "スニペット共有 / Snippet Sharing" section with a single label "Coming Soon".
  - **Snippet selected**:
    - `TextField` for title.
    - `TextEditor` for content with monospaced font option.
    - `Toggle` "有効 / Enabled" bound to `isEnabled`.
    - `KeyboardShortcuts.Recorder` for individual snippet shortcut.
  - All edits debounced 250 ms before calling `SnippetStore.updateSnippet`.
- **Dependencies**: Step 6.3, Step 5.7.
- **Verification**: Select the "Gemini用" folder; the right pane shows the layout matching the attached editor screenshot (folder icon, name, shortcut field, "Coming Soon" placeholder). Select a snippet; the layout switches to title + body editor.
- **Complexity**: Medium. **Risk**: Low.

#### Step 6.5: Toolbar actions and delete confirmation
- **Agent**: coding-agent
- **Location**: `SwiftClip/SnippetEditor/SnippetToolbar.swift`, `SwiftClip/SnippetEditor/DeleteConfirmationAlert.swift`
- **Action**: Wire toolbar buttons and the delete-confirmation alert.
- **Details**:
  - スニペット追加 — adds a new untitled snippet to the currently selected folder (or to the first folder if a snippet is selected). Auto-selects it for inline rename.
  - フォルダ追加 — adds a new untitled folder at the bottom; auto-selects for rename.
  - 削除 — opens the confirmation alert (see below). On confirm, calls `deleteSnippet` or `deleteFolder` accordingly.
  - 有効/無効 — toggles `isEnabled` on the selected node.
  - インポート — `NSOpenPanel` filtered to `.xml`. On selection, read data, call `ClipyXMLCodec.decode`, present a confirmation: "Replace existing snippets? / Append?". On replace: `SnippetStore.replaceAll(with:)`. On append: iterate and add.
  - エクスポート — `NSSavePanel` with default filename `swiftclip-snippets.xml`. Calls `ClipyXMLCodec.encode(folders: store.allFolders())` and writes.
  - **DeleteConfirmationAlert** (matches the user-supplied screenshot):
    - Uses `NSAlert` with:
      - `messageText = String(localized: "alert.delete.title")` ("スニペットを削除" / "Delete Snippet")
      - `informativeText = String(localized: "alert.delete.body")` ("本当に削除してもよろしいですか？" / "Are you sure you want to delete this?")
      - `alertStyle = .warning`
      - First button = "スニペットを削除" / "Delete Snippet" (destructive). Second button = "キャンセル" / "Cancel".
      - `icon = NSImage(named: "AppIcon")`.
    - For folders, swap `informativeText` to mention deleting all contained snippets.
- **Dependencies**: Step 6.1, Step 6.3, Step 6.4.
- **Verification**:
  - Click 削除 on a snippet; the alert appears matching the screenshot. Click Cancel — nothing changes. Click Delete — the snippet is removed from the outline and from the menu.
  - Import the user-supplied `sample-clipy.xml`; verify 2 folders and 3 snippets appear with correct titles and content (newlines preserved).
  - Export, then re-import; structure is identical.
- **Complexity**: Medium. **Risk**: Medium — XML import "replace vs append" mistake destroys data.
- **Idempotence & Recovery**: Replace-import is destructive. Before calling `replaceAll`, write the current state to `<appSupport>/Backups/snippets-pre-import-<ISO8601>.xml`. On import failure, display the backup path in the error alert so the user can recover.

#### Step 6.G: Phase Gate — Snippets
- **Agent**: review-agent
- **Action**: Manual round-trip test against the user fixture.
- **Verification**:
  - Import `sample-clipy.xml` — exactly 2 folders, exactly 3 snippets, contents match byte-for-byte.
  - Export → diff against the original file → only difference is whitespace normalization (trailing newline). The XML parses round-trip identically.
  - Delete confirmation matches the attached screenshot.
  - Snippets appear in the menu bar Snippets section and pasting one inserts its content into TextEdit.
- **Dependencies**: 6.1–6.5.

---

### Phase 7: Localization, Polish, Edge Cases

**Purpose**: After this phase, the app passes all 15 acceptance requirements in both English and Japanese, with no force-unwraps, complete string catalog, and clean memory/file-handle behavior.

#### Step 7.1: Populate Localizable.xcstrings
- **Agent**: coding-agent
- **Location**: `SwiftClip/Localization/Localizable.xcstrings`
- **Action**: Add every user-facing key with English (base) and Japanese translations.
- **Details**: Group keys by namespace: `menubar.*`, `prefs.*`, `editor.*`, `alert.*`, `onboarding.*`, `error.*`. For each `String(localized: "...")` call site introduced in Phase 1–6, add the entry. Japanese strings come directly from the spec wording in the user's GUI document.
- **Dependencies**: All earlier phases.
- **Verification**: Set system language to Japanese, relaunch, every visible string is in Japanese. Switch to English, every string is in English. No `Localized<key>` placeholders appear in the UI.
- **Complexity**: Medium. **Risk**: Low.

#### Step 7.2: Unit + integration test pass
- **Agent**: coding-agent
- **Location**: `SwiftClipTests/`
- **Action**: Ensure every test from Steps 1.4, 2.1–2.4, 3.2, 4.1, 6.1 plus the smoke tests pass; add missing tests where coverage is thin.
- **Details**: Specifically add:
  - `PreferencesStoreTests` — round-trip every preference value through SwiftData; assert defaults; assert `formatPDF` and `formatImage` default to `false`.
  - `BlobStoreDeletionTests` — explicit test that overflow eviction with `historyLimit = 3` and 5 inserts results in the oldest 2 blob files removed from `Blobs/`.
  - `MenuBuilderTitleFormattingTests` — table-driven tests of title formatting permutations (numbers on/off, zero-start, char-limit truncation).
- **Dependencies**: All preceding steps.
- **Verification**: `xcodebuild test` reports 0 failures.
- **Complexity**: Medium. **Risk**: Low.

#### Step 7.3: Refactor pass
- **Agent**: refactoring-agent
- **Location**: project-wide
- **Action**: Eliminate force-unwraps, force-tries, and TODOs; consolidate duplicated string-truncation utilities into `Support/StringTruncation.swift`; ensure every `Task` in non-detached contexts inherits the correct actor isolation.
- **Details**: Run the Swift 6 strict-concurrency build. Resolve every actor-isolation diagnostic. Replace `try!` with `try?` or proper `do/catch`. Replace `as!` with conditional casts.
- **Dependencies**: Step 7.2.
- **Verification**: `xcodebuild` Release build with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` produces 0 warnings. All tests still pass.
- **Complexity**: Medium. **Risk**: Low.

#### Step 7.G: Phase Gate — Acceptance
- **Agent**: review-agent
- **Action**: Walk through every requirement R1–R15 manually; check off each.
- **Verification**: All 15 requirements pass. Acceptance log recorded in `CHANGELOG.md`.
- **Dependencies**: 7.1, 7.2, 7.3.

---

### Phase 8: Documentation and Release Artifacts

**Purpose**: After this phase, a new contributor can clone the repo, follow `README.md`, and produce a runnable `SwiftClip.app` themselves.

#### Step 8.1: README and CHANGELOG
- **Agent**: documentation-agent
- **Location**: `README.md`, `CHANGELOG.md`
- **Action**: Replace the skeleton with full content.
- **Details**:
  - `README.md` sections, in order:
    1. Overview (one paragraph; mirror the plan's Overview).
    2. Screenshots (placeholder — `docs/screenshots/`, populated later).
    3. System Requirements (macOS 26.0+, Apple Silicon).
    4. Permissions Required — Accessibility (mandatory for paste injection), Input Monitoring (optional).
    5. Build From Source — exact `xcodebuild` command from R11; instructions for opening in Xcode and using "Product → Archive" with ad-hoc signing.
    6. Importing from Clipy — reference the XML format and the menu path: SwiftClip → スニペットを編集 → Import.
    7. Keyboard Shortcuts — list of configurable shortcut points.
    8. Privacy — local-only; no telemetry; no auto-update; clipboard data never leaves the machine.
    9. License — MIT, with the standard MIT text in `LICENSE`.
  - `CHANGELOG.md`:
    - `## [Unreleased]` heading with a summary of the bullet items implemented across Phases 1–7.
- **Dependencies**: Step 7.G.
- **Verification**: A reader following the Build From Source steps (clean checkout, `git clone`, open in Xcode 26.4, build) ends with a working `.app`. Internal review by the executing agent against this very plan: each phase's deliverable is mentioned somewhere in the README.
- **Complexity**: Low. **Risk**: Low.

#### Step 8.2: Final ad-hoc archive verification
- **Agent**: devops-agent
- **Location**: repo root
- **Action**: Produce a Release build via the documented command and verify it runs.
- **Details**:
  - Command:
    ```
    xcodebuild -project SwiftClip.xcodeproj \
               -scheme SwiftClip \
               -configuration Release \
               -destination 'platform=macOS,arch=arm64' \
               CODE_SIGN_IDENTITY="-" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=NO \
               build
    ```
  - The resulting `.app` should be in `~/Library/Developer/Xcode/DerivedData/SwiftClip-*/Build/Products/Release/SwiftClip.app`.
  - Copy it to `/Applications/`. Open it from Finder; on first launch, accept the Gatekeeper "open anyway" prompt via System Settings → Privacy & Security if prompted.
- **Dependencies**: Step 8.1.
- **Verification**: The app launches. The clipboard menu-bar icon appears. Importing the sample XML works. Pasting works after granting AX permission.
- **Complexity**: Low. **Risk**: Medium — Gatekeeper rejection on Tahoe with ad-hoc signing.
- **Idempotence & Recovery**: Build is idempotent. If Gatekeeper blocks launch, the recovery is to right-click → Open in Finder, or to add the Hardened Runtime exception. Document the workaround in README.

#### Step 8.3: Documentation review
- **Agent**: documentation-agent
- **Action**: Cross-check that the README's "Permissions Required" wording matches the actual prompts the user sees on first launch.
- **Verification**: Manual.
- **Dependencies**: 8.1, 8.2.

#### Step 8.G: Phase Gate — Release Ready
- **Agent**: review-agent
- **Action**: Final repo audit.
- **Verification**:
  - `git status` clean.
  - `xcodebuild -configuration Release` produces a launching `.app`.
  - All 15 requirements remain satisfied on the Release build.
  - `LICENSE` is MIT, attribution placeholder filled.
- **Dependencies**: 8.1, 8.2, 8.3.

---

## Risks and Mitigations

1. **Hardened Runtime + ad-hoc signing may block AX-keystroke synthesis** (Step 3.3). Mitigation: do not enable `com.apple.security.cs.disable-library-validation` unnecessarily; if `CGEvent.post` returns no effect, document the System Settings → Privacy → Accessibility workflow in README. Verified manually in Step 3.G.
2. **macOS 26 Tahoe ships its own clipboard manager** which may interact with `NSPasteboard.changeCount` semantics. Mitigation: rely on `changeCount` polling (the documented public contract) rather than internal Tahoe APIs. If anomalies surface, log and continue — log evidence in Surprises & Discoveries.
3. **KeyboardShortcuts library may not support modifier-only recording** for the Extensions tab (Step 5.8). Mitigation: a fallback custom recorder is described inline; if needed, the recorder is isolated to that tab and recorded as a Decision Log entry.
4. **SwiftData migrations** are not planned (initial schema). Mitigation: tag the schema with a version constant `SwiftClipSchemaV1` so a future schema change can introduce a `MigrationPlan` cleanly.
5. **Blob store divergence** (file on disk without index entry, or vice versa). Mitigation: `BlobStore.sweep` runs at startup and after `clearAll` (Step 2.3, 2.4).

## Success Criteria

- [ ] R1: Menu bar icon visible after launching `SwiftClip.app`; clicking it shows the four required sections in order.
- [ ] R2: A copy in TextEdit appears in History within 1 s.
- [ ] R3: Selecting a history entry pastes via ⌘V into the previously focused app.
- [ ] R4: Selecting a snippet pastes its content.
- [ ] R5: New folders/snippets appear in the menu within 500 ms of creation.
- [ ] R6: Round-trip of `sample-clipy.xml` produces an equivalent in-app structure and a re-exported file with identical content.
- [ ] R7: Delete confirmation alert matches the attached screenshot.
- [ ] R8: All preferences survive a quit/relaunch.
- [ ] R9: Custom global shortcut for "メイン" opens the menu after relaunch.
- [ ] R10: Excluded bundle ID prevents history insertion.
- [ ] R11: `xcodebuild ... CODE_SIGN_IDENTITY="-"` produces a launching `.app`.
- [ ] R12: After "履歴をクリア", `Blobs/` is empty and `History.json` is `[]`.
- [ ] R13: 60 MB image is rejected; history unchanged.
- [ ] R14: Image format is off by default — copying a screenshot does not produce an entry.
- [ ] R15: UI is fully localized to English and Japanese.
- [ ] All `XCTest`s pass: `xcodebuild test` reports 0 failures.
- [ ] Release build with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` produces 0 warnings.

---

## Progress

- [ ] Step 1.1: Repo skeleton.
- [ ] Step 1.2: Xcode project.
- [ ] Step 1.3: KeyboardShortcuts SwiftPM.
- [ ] Step 1.4: Support modules (FileLocations / Logging / Errors).
- [ ] Step 1.5: Status item with placeholder menu.
- [ ] Step 1.G: Bootstrap gate.
- [ ] Step 2.1: SwiftData models.
- [ ] Step 2.2: SnippetStore actor.
- [ ] Step 2.3: BlobStore.
- [ ] Step 2.4: HistoryStore.
- [ ] Step 2.G: Persistence gate.
- [ ] Step 3.1: PermissionsProbe.
- [ ] Step 3.2: PasteboardWatcher.
- [ ] Step 3.3: PasteEngine.
- [ ] Step 3.4: Onboarding window.
- [ ] Step 3.G: Capture & paste gate.
- [ ] Step 4.1: Menu section builders.
- [ ] Step 4.2: MainMenuBuilder integration.
- [ ] Step 4.G: Menu-bar UI gate.
- [ ] Step 5.1: PreferencesStore wrapper.
- [ ] Step 5.2: Preferences window shell.
- [ ] Step 5.3: 一般 tab.
- [ ] Step 5.4: メニュー tab.
- [ ] Step 5.5: 対応形式 tab.
- [ ] Step 5.6: 除外アプリ tab.
- [ ] Step 5.7: ショートカット tab + ShortcutNames.
- [ ] Step 5.8: 拡張機能 tab.
- [ ] Step 5.G: Preferences gate.
- [ ] Step 6.1: Clipy XML codec.
- [ ] Step 6.2: Editor window scaffold.
- [ ] Step 6.3: Outline view.
- [ ] Step 6.4: Detail pane.
- [ ] Step 6.5: Toolbar actions + delete alert.
- [ ] Step 6.G: Snippets gate.
- [ ] Step 7.1: Localization catalog.
- [ ] Step 7.2: Test pass.
- [ ] Step 7.3: Refactor pass.
- [ ] Step 7.G: Acceptance gate.
- [ ] Step 8.1: README + CHANGELOG.
- [ ] Step 8.2: Release archive verification.
- [ ] Step 8.3: Documentation review.
- [ ] Step 8.G: Release-ready gate.

## Decision Log

*To be populated by Codex during execution. Entry format:*
```
- Decision: <what was decided>
  Rationale: <why>
  Date: <YYYY-MM-DD>
```

## Surprises & Discoveries

*To be populated by Codex during execution. Entry format:*
```
- Observation: <what was observed>
  Evidence: <log excerpt, error message, or test output>
```

## Outcomes & Retrospective

*To be written at the end of each phase gate and at completion.*
