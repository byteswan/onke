import SwiftUI

/// The "Save power" panel section (spec §7): individual system toggles plus the one-button
/// Cleanup with Undo. Controls whose underlying API is unavailable on this machine are
/// hidden rather than shown disabled.
struct SavePowerView: View {
    @ObservedObject var cleanup: CleanupCoordinator
    let toggles: SystemToggles

    @State private var lowPowerOn = false
    @State private var wifiOn = true
    @State private var bluetoothOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save power")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // One-button cleanup + undo.
            HStack {
                Button {
                    cleanup.runCleanup()
                } label: {
                    Label("Cleanup", systemImage: "sparkles")
                }
                .disabled(cleanup.isBusy)

                if cleanup.lastUndo != nil {
                    Button("Undo") { cleanup.undo() }
                }
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
            Toggle("Low Power Mode", isOn: $lowPowerOn)
                .onChange(of: lowPowerOn) { on in toggles.setLowPowerMode(on) }

            if toggles.wifiAvailable {
                Toggle("Wi-Fi", isOn: $wifiOn)
                    .onChange(of: wifiOn) { on in toggles.setWiFi(on: on) }
            }
            if toggles.bluetoothAvailable {
                Toggle("Bluetooth", isOn: $bluetoothOn)
                    .onChange(of: bluetoothOn) { on in toggles.setBluetooth(on: on) }
            }
            if toggles.brightnessAvailable {
                Button("Dim screen") { toggles.lowerBrightness(to: 0.2) }
                    .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .font(.caption)
        .onAppear {
            wifiOn = toggles.wifiIsOn
        }
    }
}
