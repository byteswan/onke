import SwiftUI
import ServiceManagement

/// The settings pane (spec §5.4), shown *inside* the main window (``ContentView`` flips
/// to it — settings never opens a separate window). Binds directly to ``AppSettings``
/// (UserDefaults) and toggles the login item via `SMAppService.mainApp`.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Sampling") {
                // Interval affects CPU cost; the spec floor is 5s. Change applies on
                // next launch (the running timer isn't hot-swapped in phase 1).
                Slider(value: $settings.samplingInterval, in: 5...30, step: 1) {
                    Text("Interval")
                } minimumValueLabel: { Text("5s") } maximumValueLabel: { Text("30s") }
                Text("\(Int(settings.samplingInterval))s between readings (applies on restart)")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                LabeledContent("Low-battery alert") {
                    Stepper("\(Int(settings.timeLowMinutes)) min",
                            value: $settings.timeLowMinutes, in: 15...240, step: 5)
                }
                LabeledContent("Re-arm above") {
                    Stepper("\(Int(settings.timeLowRearmMinutes)) min",
                            value: $settings.timeLowRearmMinutes, in: 20...300, step: 5)
                }
                LabeledContent("Drain-spike sensitivity") {
                    Stepper(String(format: "%.1f×", settings.drainSpikeMultiplier),
                            value: $settings.drainSpikeMultiplier, in: 1.1...3.0, step: 0.1)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        LaunchAtLogin.set(enabled)
                        // Re-read actual state in case the toggle failed.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// Thin wrapper over `SMAppService.mainApp` for the login-item toggle (spec §5.4).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Onke: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
