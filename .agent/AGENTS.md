# SwiftClip Agent Rules

These rules are repo-local guardrails for future AI agents working on SwiftClip. They exist to avoid repeating problems already encountered during the initial app implementation.

## Build Workflow

- Treat `SwiftClip.xcodeproj` as the primary project. Do not convert the app to a SwiftPM-only project.
- Use the Xcode MCP server for build/test/project inspection only when an Xcode project is already open and the server is available.
- If no Xcode project is open, use `xcodebuild` directly. This is the approved fallback for this repo.
- Build for macOS Apple Silicon with:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

- Run tests with:

```sh
xcodebuild -project SwiftClip.xcodeproj -scheme SwiftClip -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/swiftclip-derived CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

- Do not pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the `xcodebuild` command line. It applies to package dependencies and can conflict with `KeyboardShortcuts`. Keep warnings-as-errors scoped to the SwiftClip app target build settings.

## Dependencies

- Keep `KeyboardShortcuts` as an Xcode package dependency from `https://github.com/sindresorhus/KeyboardShortcuts.git`, version `2.4.0` or newer compatible release.
- If package resolution fails, resolve packages through Xcode or rerun `xcodebuild -list -project SwiftClip.xcodeproj` with network permission.
- Do not vendor or reimplement keyboard-shortcut capture unless the dependency becomes unusable.

## Swift And Concurrency

- Preserve Swift 6 strict concurrency settings.
- Keep AppKit, NSPasteboard, NSStatusItem, NSWindow, and Accessibility API usage on the main actor unless there is a proven safe boundary.
- For Accessibility trust prompting, use the string key `"AXTrustedCheckOptionPrompt"` in the options dictionary. Do not use `kAXTrustedCheckOptionPrompt` directly; it previously caused Swift 6 diagnostics.
- Do not import `FoundationXML` for the Clipy XML codec. Use `Foundation.XMLParser` APIs from `Foundation`.

## Xcode Project Hygiene

- Keep `Resources/Info.plist` and `Resources/SwiftClip.entitlements` excluded from copied resources in the synchronized Xcode project configuration.
- Keep `LSUIElement = true` in the app Info.plist so SwiftClip remains a menu-bar accessory app.
- Keep the deployment target at macOS `26.0` or later unless the user explicitly asks for a lower baseline.
- The non-fatal Xcode warning `Metadata extraction skipped. No AppIntents.framework dependency found.` is known. Do not add AppIntents just to silence it unless SwiftClip actually gains AppIntents features.

## Runtime Verification

- After code edits, run at least one build. Run tests when behavior or persistence changes.
- Use the provided launch check for GUI verification:

```sh
./script/build_and_run.sh --verify
```

- GUI launch and process checks may require sandbox escalation. Request it instead of replacing the verification with a weaker check.
- Manual Accessibility paste injection requires approving SwiftClip in System Settings. Do not mark paste injection fully verified without that approval and a real paste target.

## Persistence And Clipboard Behavior

- Preserve the separation between JSON metadata and blob files. Do not inline large binary payloads into history JSON.
- Keep self-capture suppression around app-initiated pasteboard writes, or selecting a menu item can duplicate it in history.
- Preserve deterministic tests for history, preferences, blob storage, and Clipy XML import/export when changing those areas.
- SwiftData model types are present, but the current stores are file-backed for deterministic behavior. Do not silently migrate persistence without tests and a compatibility plan.

## Notes

- Record new build failures, warnings, manual verification gaps, and fixes in `.agent/NOTES.md`.
- Keep `.agent/NOTES.md` factual and handoff-oriented; avoid work-log narration.
