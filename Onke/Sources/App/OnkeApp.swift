import SwiftUI

/// App entry point. Onke is menu-less: there is no ordinary window and no dock
/// presence — a floating `NSPanel` (owned by ``AppDelegate``) is the whole UI, plus a
/// menu bar extra for quit/settings (spec §5.2). The panel has no close box; closing =
/// quitting from the menu bar.
@main
struct OnkeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(engine: appDelegate.engine)
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

/// The menu bar dropdown: a compact status readout plus lifecycle actions. Settings is a
/// placeholder for now (spec §5.4 lands in a later pass).
private struct MenuBarContent: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        if let s = engine.sample, s.hasBattery {
            Text(String(format: "%+.1f W · %d%%", s.netWatts, Int(s.percentage.rounded())))
        } else {
            Text("No battery detected")
        }
        Divider()
        Button("Quit Onke") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
