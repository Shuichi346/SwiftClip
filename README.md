# SwiftClip

SwiftClip is a menu-bar clipboard history manager and snippet launcher for macOS 26 and later. It stores clipboard history locally, supports reusable snippet folders, and can paste selected items back into the previously focused app after Accessibility permission is granted.

## Screenshots

Screenshots will live in `docs/screenshots/` as the interface stabilizes.

## System Requirements

SwiftClip targets macOS 26.0 or later on Apple Silicon. Build with Xcode 26.4 or newer.

## Permissions Required

Accessibility permission is required for automatic paste injection because SwiftClip synthesizes Command-V after you choose a menu item. Input Monitoring is optional and is only relevant for future shortcut-related diagnostics.

## Build From Source

Open `SwiftClip.xcodeproj` in Xcode and build the `SwiftClip` scheme, or run:

```sh
xcodebuild -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Importing From Clipy

Open `SwiftClip` from the menu bar, choose `Snippet Editor`, and use Import to load Clipy-compatible XML with `folders > folder > snippets > snippet > title/content`.

## Keyboard Shortcuts

Shortcuts are user-configurable in Preferences. The Main shortcut opens the standalone History/Snippets popup next to the cursor; editor, preferences, clear-history, and extension-style paste actions also use the KeyboardShortcuts package.

## Privacy

SwiftClip is local-only. Clipboard history, snippets, and preferences are stored under `~/Library/Application Support/SwiftClip`, and no telemetry or network sync is included.

## License

MIT. See `LICENSE`.
