import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    private var statusItemController: StatusItemController?
    private var pasteboardWatcher: PasteboardWatcher?
    private var preferencesWindow: NSWindow?
    private var snippetEditorWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        environment.openPreferences = { [weak self] in
            self?.showPreferencesWindow()
        }
        environment.openSnippetEditor = { [weak self] in
            self?.showSnippetEditorWindow()
        }
        environment.openPermissions = { [weak self] in
            self?.showPermissionsWindow()
        }

        environment.start()

        let controller = StatusItemController(environment: environment)
        statusItemController = controller

        let watcher = PasteboardWatcher(environment: environment)
        pasteboardWatcher = watcher
        environment.pasteEngine.onPasteboardWrite = { [weak watcher] in
            watcher?.suppressNextChange()
        }
        watcher.start()

        KeyboardShortcuts.onKeyUp(for: .mainMenu) { [weak self] in
            Task { @MainActor in
                self?.statusItemController?.showMenu()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .clearHistory) { [weak self] in
            Task { @MainActor in
                self?.environment.history.clearAll()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .snippetEditor) { [weak self] in
            Task { @MainActor in
                self?.showSnippetEditorWindow()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .preferences) { [weak self] in
            Task { @MainActor in
                self?.showPreferencesWindow()
            }
        }

        if !PermissionsProbe.isAccessibilityTrusted(prompt: false) {
            showPermissionsWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showPreferencesWindow() {
        if let preferencesWindow {
            present(window: preferencesWindow)
            return
        }

        let rootView = PreferencesWindow(environment: environment)
        let window = makeWindow(
            title: L10n.string("prefs.window.title"),
            size: NSSize(width: 620, height: 520),
            rootView: rootView
        )
        preferencesWindow = window
        present(window: window)
    }

    private func showSnippetEditorWindow() {
        if let snippetEditorWindow {
            present(window: snippetEditorWindow)
            return
        }

        let rootView = SnippetEditorWindow(environment: environment)
        let window = makeWindow(
            title: L10n.string("editor.window.title"),
            size: NSSize(width: 768, height: 500),
            rootView: rootView
        )
        snippetEditorWindow = window
        present(window: window)
    }

    private func showPermissionsWindow() {
        if let permissionsWindow {
            present(window: permissionsWindow)
            return
        }

        let rootView = PermissionsWindow()
        let window = makeWindow(
            title: L10n.string("onboarding.window.title"),
            size: NSSize(width: 520, height: 360),
            rootView: rootView
        )
        permissionsWindow = window
        present(window: window)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.setContentSize(size)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
