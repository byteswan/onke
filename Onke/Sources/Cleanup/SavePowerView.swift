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
    /// Brightness toggle: on = dim to 40%, off = restore to 80%.
    @State private var brightnessDimmed = false

    private typealias Tips = Strings.SavePower.Tips

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One-button cleanup + undo.
            HStack {
                Button {
                    cleanup.runCleanup()
                } label: {
                    Label(Strings.SavePower.cleanupButton, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)
                .disabled(cleanup.isBusy)

                if cleanup.lastUndo != nil {
                    Button(Strings.SavePower.undo) { cleanup.undo() }
                }

                InfoTip(text: Tips.cleanup)
            }
            .controlSize(.small)

            // Apps suggested for quitting after a cleanup (listed, never auto-killed).
            ForEach(cleanup.suggestedQuits) { app in
                HStack(spacing: 6) {
                    Text(app.name).font(.caption).lineLimit(1)
                    Spacer()
                    Button(Strings.SavePower.quit) { cleanup.quit(app) }
                        .controlSize(.mini)
                }
            }

            Divider().padding(.vertical, 2)

            // Individual toggles — each hidden when unavailable.
            toggleRow(Strings.SavePower.lowPowerMode, tip: Tips.lowPower, isOn: $lowPowerOn)
                .onChange(of: lowPowerOn) { on in toggles.setLowPowerMode(on) }

            if toggles.wifiAvailable {
                toggleRow(Strings.SavePower.wifi, tip: Tips.wifi, isOn: $wifiOn)
                    .onChange(of: wifiOn) { on in toggles.setWiFi(on: on) }
            }
            if toggles.bluetoothAvailable {
                toggleRow(Strings.SavePower.bluetooth, tip: Tips.bluetooth, isOn: $bluetoothOn)
                    .onChange(of: bluetoothOn) { on in toggles.setBluetooth(on: on) }
            }
            if toggles.brightnessAvailable {
                toggleRow(Strings.SavePower.screenBrightness, tip: Tips.brightness,
                          isOn: $brightnessDimmed)
                    .onChange(of: brightnessDimmed) { dimmed in
                        toggles.lowerBrightness(to: dimmed ? 0.4 : 0.8)
                    }
            }
        }
        .font(.callout)
        .onAppear {
            wifiOn = toggles.wifiIsOn
            if let b = toggles.currentBrightness { brightnessDimmed = b <= 0.5 }
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
