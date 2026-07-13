import SwiftUI

/// App entry point. Onke is a normal windowed Mac app: a single main window (SwiftUI
/// `Window` scene, so macOS restores its position/size automatically) plus a menu bar
/// extra with the battery % and quick actions. Closing the window keeps Onke running in
/// the menu bar so monitoring and notifications continue.
@main
struct OnkeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(Strings.App.name, id: "main") {
            ContentView(engine: appDelegate.engine,
                        settings: appDelegate.settings,
                        ui: appDelegate.ui,
                        helper: appDelegate.helper,
                        cleanup: appDelegate.cleanup,
                        toggles: appDelegate.toggles,
                        ledger: appDelegate.ledger)
        }
        // The in-content header row is the chrome; the system title bar is hidden and
        // the traffic lights float over it (ContentView leaves them clearance).
        .windowStyle(.hiddenTitleBar)
        // Fixed-size window: the content declares an exact frame and the window can't
        // be resized past it.
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(engine: appDelegate.engine, ui: appDelegate.ui)
        } label: {
            // Battery % as a secondary affordance in the menu bar.
            if let s = appDelegate.engine.sample, s.hasBattery {
                Text("\(Int(s.percentage.rounded()))%")
            } else {
                Image(systemName: "bolt.fill")
            }
        }
    }
}

/// The menu bar dropdown: a compact status readout plus lifecycle actions.
private struct MenuBarContent: View {
    @ObservedObject var engine: MetricsEngine
    @ObservedObject var ui: UIState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let s = engine.sample, s.hasBattery {
            Text(Strings.App.menuStatus(watts: s.netWatts, percent: Int(s.percentage.rounded())))
        } else {
            Text(Strings.App.noBatteryDetected)
        }
        Divider()
        Button(Strings.App.openOnke) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(Strings.App.powerHistory) {
            ui.screen = .analytics
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(Strings.App.settingsMenuItem) {
            ui.screen = .settings
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button(Strings.App.quitOnke) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
