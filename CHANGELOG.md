# Changelog

## [Unreleased]

- Bootstrapped the SwiftClip macOS menu-bar app.
- Added local clipboard history, snippet management, preferences, shortcuts, localization, and build/run documentation.
- Added the app icon as `SwiftClip/Resources/AppIcon.icns` and wired it through `CFBundleIconFile` for Xcode builds and packaged app bundles.
- Changed the `Main` global shortcut to open a standalone History/Snippets popup next to the cursor instead of opening the menu-bar status item menu.
