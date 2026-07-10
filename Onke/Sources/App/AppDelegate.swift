import AppKit
import SwiftUI

/// Owns the long-lived app objects: settings, the metrics engine, the notification
/// engine, and the privileged-helper client. The window itself is a SwiftUI `Window`
/// scene in ``OnkeApp``; the delegate only handles lifecycle that SwiftUI doesn't
/// (dock-icon reopen).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settings = AppSettings.shared

    /// Single metrics engine shared by the main window and the menu bar extra.
    let engine: MetricsEngine

    /// Transient UI state (in-window settings flip) shared with the menu bar extra.
    let ui = UIState()

    private let notifications: NotificationEngine
    /// Hourly in/out energy history (the "Power history" screen).
    let ledger = EnergyLedger()
    let helper = HelperClient()
    lazy var toggles = SystemToggles(helper: helper)
    lazy var cleanup = CleanupCoordinator(toggles: toggles, helper: helper)

    override init() {
        // Normal launch reads live IOKit battery data. The hidden `--demo` launch argument
        // (spec §5.5) swaps in a scripted source so all states + notifications are
        // reachable without a real battery. The test-only FakePowerSource is separate.
        let provider: PowerSourceProviding =
            ProcessInfo.processInfo.arguments.contains("--demo")
                ? DemoPowerSource()
                : IOKitPowerSource()
        engine = MetricsEngine(provider: provider, interval: settings.samplingInterval)
        notifications = NotificationEngine(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifications.attach(to: engine, helper: helper)
        ledger.attach(to: engine, expectedInterval: settings.samplingInterval)
        engine.start()
        // Reflect the helper's current approval state; connect if already enabled from a
        // previous session. First-time enabling happens on user action in the per-app UI.
        helper.refreshState()
        if helper.state == .enabled { helper.connect() }
    }

    /// Clicking the dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
