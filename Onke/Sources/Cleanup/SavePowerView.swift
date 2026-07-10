import SwiftUI

/// The "Save power" card content (spec §7): the one-button Cleanup with Undo, then
/// individual system toggles as full-width rows (label leading, control trailing, so
/// every switch lands on the same column). Every option carries an ⓘ tip stating
/// exactly what pressing it does. Controls whose underlying API is unavailable on this
/// machine are hidden rather than shown disabled.
struct SavePowerView: View {
    @ObservedObject var cleanup: CleanupCoordinator
    let toggles: SystemToggles

    @State private var lowPowerOn = false
    @State private var wifiOn = true
    @State private var bluetoothOn = true

    private enum Tips {
        static let cleanup = """
        One click does all of this:
        • Turns on Low Power Mode (via the privileged helper)
        • Drops screen brightness to 20%
        • Lists the top 3 energy-hungry apps below with Quit buttons — nothing is quit automatically

        Undo restores your previous brightness and turns Low Power Mode back off.
        """
        static let lowPower = "Toggles macOS Low Power Mode (pmset, via the privileged helper). Reduces CPU performance and background activity to stretch the battery."
        static let wifi = "Turns Wi-Fi on or off — same as the menu bar toggle. Uses CoreWLAN, falling back to networksetup via the helper if macOS blocks it."
        static let bluetooth = "Turns Bluetooth on or off (uses the blueutil tool installed on this Mac). Disconnects Bluetooth accessories while off."
        static let brightness = "Sets the built-in display's brightness to 20%. Restore it with the brightness keys or Cleanup's Undo."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One-button cleanup + undo.
            HStack {
                Button {
                    cleanup.runCleanup()
                } label: {
                    Label("Cleanup", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)
                .disabled(cleanup.isBusy)

                if cleanup.lastUndo != nil {
                    Button("Undo") { cleanup.undo() }
                }

                InfoTip(text: Tips.cleanup)
            }
            .controlSize(.small)

            // Apps suggested for quitting after a cleanup (listed, never auto-killed).
            ForEach(cleanup.suggestedQuits) { app in
                HStack(spacing: 6) {
                    Text(app.name).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Quit") { cleanup.quit(app) }
                        .controlSize(.mini)
                }
            }

            Divider().padding(.vertical, 2)

            // Individual toggles — each hidden when unavailable.
            toggleRow("Low Power Mode", tip: Tips.lowPower, isOn: $lowPowerOn)
                .onChange(of: lowPowerOn) { on in toggles.setLowPowerMode(on) }

            if toggles.wifiAvailable {
                toggleRow("Wi-Fi", tip: Tips.wifi, isOn: $wifiOn)
                    .onChange(of: wifiOn) { on in toggles.setWiFi(on: on) }
            }
            if toggles.bluetoothAvailable {
                toggleRow("Bluetooth", tip: Tips.bluetooth, isOn: $bluetoothOn)
                    .onChange(of: bluetoothOn) { on in toggles.setBluetooth(on: on) }
            }
            if toggles.brightnessAvailable {
                HStack(spacing: 6) {
                    Text("Screen brightness")
                    InfoTip(text: Tips.brightness)
                    Spacer()
                    Button("Dim") { toggles.lowerBrightness(to: 0.2) }
                }
            }
        }
        .font(.callout)
        .onAppear {
            wifiOn = toggles.wifiIsOn
        }
    }

    /// Full-width row: label + ⓘ leading, switch pinned trailing.
    private func toggleRow(_ title: String, tip: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
            InfoTip(text: tip)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
