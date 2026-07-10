import AppKit
import SwiftUI

/// Lazily creates and shows a standard titled window hosting ``SettingsView``. An accessory
/// (`LSUIElement`) app has no default window and no Settings menu, so the gear button on
/// the panel drives this directly.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Onke Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        // Momentarily become a regular app so the settings window can take focus, then
        // the panel stays non-activating as before.
        NSApp.activate(ignoringOtherApps: true)
    }
}
