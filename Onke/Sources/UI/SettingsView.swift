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
            Section(Strings.Settings.samplingSection) {
                // Interval affects CPU cost; the spec floor is 5s. Change applies on
                // next launch (the running timer isn't hot-swapped in phase 1).
                Slider(value: $settings.samplingInterval, in: 5...30, step: 1) {
                    Text(Strings.Settings.interval)
                } minimumValueLabel: { Text(Strings.Settings.intervalMin) }
                  maximumValueLabel: { Text(Strings.Settings.intervalMax) }
                Text(Strings.Settings.intervalCaption(seconds: Int(settings.samplingInterval)))
                    .font(.caption).foregroundColor(.secondary)
            }

            Section(Strings.Settings.notificationsSection) {
                Toggle(Strings.Settings.enableNotifications, isOn: $settings.notificationsEnabled)
                // Time-remaining alert + its re-arm, phrased as a pair: the second row is
                // indented under the first to show it only governs when the alert repeats.
                LabeledContent {
                    Stepper(Strings.Settings.minutes(Int(settings.timeLowMinutes)),
                            value: $settings.timeLowMinutes, in: 15...240, step: 5)
                } label: {
                    labelWithTip(Strings.Settings.warnUnder, tip: Strings.Settings.warnUnderTip)
                }
                LabeledContent {
                    Stepper(Strings.Settings.minutes(Int(settings.timeLowRearmMinutes)),
                            value: $settings.timeLowRearmMinutes, in: 20...300, step: 5)
                } label: {
                    labelWithTip(Strings.Settings.stopWarningAbove, tip: Strings.Settings.stopWarningAboveTip)
                        .padding(.leading, 16)
                }
                LabeledContent {
                    Stepper(Strings.Settings.multiplier(settings.drainSpikeMultiplier),
                            value: $settings.drainSpikeMultiplier, in: 1.1...3.0, step: 0.1)
                } label: {
                    labelWithTip(Strings.Settings.drainSpikeAlert, tip: Strings.Settings.drainSpikeTip)
                }
            }

            Section(Strings.Settings.perAppSection) {
                Toggle(Strings.Settings.showSystemProcesses, isOn: $settings.showSystemProcesses)
                Text(Strings.Settings.showSystemProcessesCaption)
                    .font(.caption).foregroundColor(.secondary)
            }

            Section(Strings.Settings.generalSection) {
                Toggle(Strings.Settings.launchAtLogin, isOn: $launchAtLogin)
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

    /// A settings-row label with an ⓘ tip explaining what the adjacent control does.
    private func labelWithTip(_ title: String, tip: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            InfoTip(text: tip)
        }
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
