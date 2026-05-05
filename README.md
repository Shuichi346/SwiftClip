<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# SwiftClip

SwiftClip is a local-first macOS menu-bar clipboard manager and snippet launcher for macOS 26.0 or later. Reproducing the UI and usability of Clipy/Clipy. It keeps clipboard history, reusable snippets, preferences, and import/export data on the user's Mac, then pastes selected history or snippet items back into the previously focused app after Accessibility permission is granted.

## UI Preview

<img src="GitHub Documents/swiftclip-snippet-editor.png" alt="SwiftClip snippet editor window" width="480">

The snippet editor organizes folders and snippets in a sidebar, with editable snippet details, enablement, shortcut recording, and a large content editor in the detail pane.

## Features

- Menu-bar clipboard history with configurable item limits and title length.
- Reusable snippet folders and snippet items with per-item enablement.
- Standalone History/Snippets popup opened from a configurable global shortcut.
- Snippet editor with drag-and-drop folder ordering, snippet ordering, and cross-folder snippet moves.
- Clipy-compatible XML import and export for snippet migration.
- Format filtering for plain text, RTF, RTFD, file URLs, URLs, PDFs, and images.
- Excluded bundle IDs for apps that should not be captured.
- Local JSON metadata storage with separate blob files for larger clipboard payloads.
- Launch-at-login preference backed by Service Management.

## Tech Stack

- Swift 6
- SwiftUI and AppKit
- SwiftData model definitions for preferences scaffolding, with current stores backed by local JSON files
- KeyboardShortcuts 2.4.0 or newer compatible release
- Xcode project-based macOS app build

## Requirements

- macOS 26.0 or later
- Apple Silicon Mac
- Xcode 26.4 or later
- Accessibility permission for automatic paste injection

## Build From Source

Open `SwiftClip.xcodeproj` in Xcode and build the `SwiftClip` scheme.

For a command-line Debug build:

```sh
xcodebuild -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/swiftclip-derived \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For local build-and-launch verification:

```sh
./script/build_and_run.sh --verify
```

## Testing

Run the full test suite with:

```sh
xcodebuild -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/swiftclip-derived \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The tests cover blob storage, Clipy XML import/export, history persistence, menu title formatting, preferences persistence, and snippet reordering behavior.

## Usage

1. Launch SwiftClip.
2. Grant Accessibility permission when prompted if you want SwiftClip to paste selected items into the previously focused app.
3. Use the menu-bar item to browse clipboard history, snippets, preferences, and app actions.
4. Configure shortcuts in Preferences.
5. Open Snippet Editor to create folders, edit snippets, assign snippet shortcuts, import Clipy XML, or export SwiftClip snippets.

## Local Data

SwiftClip stores app data under:

```text
~/Library/Application Support/SwiftClip
```

Clipboard blobs are stored separately from the JSON history index so large binary payloads do not bloat metadata files.

## Project Structure

```text
SwiftClip/
  App/              App lifecycle and environment wiring
  Clipboard/        Clipboard capture, history, blob storage, and paste support
  MenuBar/          Menu-bar and standalone popup menu builders
  Onboarding/       Permission prompt UI
  Preferences/      Preferences store and settings tabs
  SnippetEditor/    Snippet editor window, outline, toolbar, and detail pane
  Snippets/         Snippet models, store, and Clipy XML codec
  Support/          Shared logging, localization, errors, and file locations
SwiftClipTests/     XCTest coverage for persistence, menus, blobs, XML, and ordering
script/             Local build and launch helper
```

## Troubleshooting

- If package resolution fails, open `SwiftClip.xcodeproj` in Xcode and resolve packages, or rerun `xcodebuild -list -project SwiftClip.xcodeproj` with network access.
- If automatic paste does not work, confirm SwiftClip is approved in System Settings for Accessibility.
- The Xcode warning `Metadata extraction skipped. No AppIntents.framework dependency found.` is known for this project and is not a build failure.

## License

MIT. See `LICENSE`.
