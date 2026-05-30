# Changelog

## [Unreleased]

- Bootstrapped the SwiftClip macOS menu-bar app.
- Added local clipboard history, snippet management, preferences, shortcuts, localization, and build/run documentation.
- Added the app icon as `SwiftClip/Resources/AppIcon.icns` and wired it through `CFBundleIconFile` for Xcode builds and packaged app bundles.
- Changed the `Main` global shortcut to open a standalone History/Snippets popup next to the cursor instead of opening the menu-bar status item menu.
- Added hover previews for snippet menu items and flattened the menu-bar Snippets section so folders are visible directly below the Snippets header.
- Added drag-and-drop reordering for snippet folders and snippets, including moving snippets between folders.
- Declared the snippet outline drag payload UTI in `Info.plist` and widened outline row drop targets so snippets can be moved between folders by dropping anywhere on the destination row.
- Fixed startup loading of persisted clipboard history and aligned the snippet outline drag payload UTI with the app's exported type declaration.
- Migrated the snippet sidebar to `NSOutlineView` so cross-folder snippet drag-and-drop works reliably.
- Added snippet attachments for local files, images, and videos so snippets can paste file objects with optional text instead of pasting absolute paths as text.
- Fixed mixed text-and-attachment snippet pasting so text and files are written as separate pasteboard items, with an app-configurable auto-paste path for apps that route file pastes through upload handling.
- Added a Mixed Snippet Paste Apps preference list so users can choose which bundle IDs use the two-step text-then-attachments paste workaround.
- Kept Mixed Snippet Paste Apps empty by default so no app receives the two-step workaround until the user adds it.
- Changed app-list preferences to add applications through a standard app picker instead of requiring manual bundle ID entry.
- Changed app-list preference rows to show resolved `.app` names while keeping bundle IDs as the stored value.
- Fixed history item pasting so failed pasteboard writes, including invalid file URL history entries, do not trigger auto-paste side effects or clear the existing clipboard.
- Normalized snippet folder and snippet ordering on load so persisted `sortIndex` values remain canonical after reload.
- Removed the Extensions preferences for delete-on-select and delete-after-paste, leaving only the plain-text paste trigger.
