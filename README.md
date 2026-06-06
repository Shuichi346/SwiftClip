<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# SwiftClip

SwiftClip is a local-first macOS menu-bar clipboard manager and snippet launcher for macOS 26.0 or later, inspired by the UI and usability of Clipy. It keeps clipboard history, reusable snippets, snippet attachments, preferences, and import/export data on the user's Mac, then pastes selected history or snippet items back into the previously focused app once Accessibility permission is granted. Built with Swift 6, SwiftUI, and AppKit, it supports Clipy-compatible XML import/export, global shortcuts, app-specific capture rules, and mixed text-and-attachment snippet pasting.

## Contents

- [UI Preview](#ui-preview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Requirements](#requirements)
- [Build From Source](#build-from-source)
- [Testing](#testing)
- [Usage](#usage)
- [Preferences](#preferences)
- [Local Data](#local-data)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## UI Preview

<img src="GitHub Documents/swiftclip-snippet-editor.png" alt="SwiftClip snippet editor window" width="480">

The snippet editor organizes folders and snippets in a sidebar, with editable snippet details, enablement, shortcut recording, and a large content editor in the detail pane.

## Features

- Menu-bar clipboard history with configurable item limits and title length.
- Reusable snippet folders and snippet items with per-item enablement.
- Standalone History/Snippets popup opened from a configurable global shortcut.
- Snippet editor with drag-and-drop folder ordering, snippet ordering, and cross-folder snippet moves.
- Snippet attachments for local files, images, and videos, with optional prompt text.
- Mixed snippet paste support that can paste text first and attachments second for selected apps.
- Clipy-compatible XML import and export for snippet migration.
- Format filtering for plain text, RTF, RTFD, file URLs, URLs, PDFs, and images.
- App-specific preferences for excluded capture apps and mixed-snippet paste apps, selected through a standard app picker.
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
5. Open Snippet Editor to create folders, edit snippets, attach files, assign snippet shortcuts, import Clipy XML, or export SwiftClip snippets.

## Preferences

SwiftClip preferences are stored locally as JSON and are available from the menu-bar app.

- **General**: launch at login and automatic paste after selecting a history item or snippet.
- **Menu**: visible numbering and menu title length.
- **Formats**: which pasteboard formats SwiftClip captures for history.
- **Apps**: applications excluded from clipboard capture, plus **Mixed Snippet Paste Apps** for apps that should receive mixed snippets as two paste operations: text first, then attachments.
- **Shortcuts**: global shortcuts for the main popup, snippet editor, preferences, and clear history actions.
- **Extensions**: modifier-triggered plain-text paste behavior.

The app lists store bundle identifiers internally, but the preferences UI resolves installed apps and displays names such as `Firefox.app` for clarity. If an app cannot be resolved, SwiftClip falls back to showing the bundle ID.

## Local Data

SwiftClip stores app data under:

```text
~/Library/Application Support/SwiftClip
```

Clipboard blobs are stored separately from the JSON history index so large binary payloads do not bloat metadata files.

Current local files include:

- `Preferences.json`
- `History.json`
- `Snippets.json`
- `Blobs/`

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
- If a mixed text-and-attachment snippet only pastes one part in a chat or upload field, add that app to **Preferences → Apps → Mixed Snippet Paste Apps**.
- The Xcode warning `Metadata extraction skipped. No AppIntents.framework dependency found.` is known for this project and is not a build failure.

## License

MIT. See `LICENSE`.
