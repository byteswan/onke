import AppKit
import SwiftUI

/// Owns the long-lived app objects: the metrics engine and the floating panel. Kept as an
/// `NSApplicationDelegate` because the panel needs direct AppKit control that the
/// SwiftUI `App` lifecycle doesn't expose cleanly.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Single metrics engine shared by the panel and the menu bar extra.
    let engine: MetricsEngine

    private var panel: FloatingPanel<PanelView>?

    override init() {
        // Vertical slice: drive everything from the fake provider. A launch argument
        // selects the demo scenario so all states are reachable without a real battery.
        // `--demo weakPowerbank` exercises the amber "plugged in but draining" case.
        let scenario = Self.scenarioFromLaunchArgs()
        let provider = FakePowerSource(scenario: scenario)
        engine = MetricsEngine(provider: provider)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-less accessory app: no dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        engine.start()

        let panel = FloatingPanel(rootView: PanelView(engine: engine))
        panel.present()
        self.panel = panel
    }

    private static func scenarioFromLaunchArgs() -> FakePowerSource.Scenario {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else {
            return .discharge
        }
        switch args[i + 1] {
        case "weakPowerbank": return .weakPowerbank
        case "healthyCharge": return .healthyCharge
        case "fullCycle": return .fullCycle
        default: return .discharge
        }
    }
}
