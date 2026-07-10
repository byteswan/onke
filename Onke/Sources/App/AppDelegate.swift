import AppKit
import SwiftUI

/// Owns the long-lived app objects: settings, the metrics engine, the notification engine,
/// and the floating panel. Kept as an `NSApplicationDelegate` because the panel needs
/// direct AppKit control that the SwiftUI `App` lifecycle doesn't expose cleanly.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settings = AppSettings.shared

    /// Single metrics engine shared by the panel and the menu bar extra.
    let engine: MetricsEngine

    private let notifications: NotificationEngine
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var panel: FloatingPanel<PanelView>?

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
        // Menu-less accessory app: no dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        notifications.attach(to: engine)
        engine.start()

        let root = PanelView(engine: engine, settings: settings) { [weak self] in
            self?.openSettings()
        }
        let panel = FloatingPanel(rootView: root)
        panel.present()
        self.panel = panel
    }

    func openSettings() {
        settingsWindow.show()
    }
}
