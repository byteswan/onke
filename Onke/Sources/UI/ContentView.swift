import SwiftUI

/// Transient UI state shared between the main window and the menu bar extra (which
/// screen the window shows). Not persisted.
@MainActor
final class UIState: ObservableObject {
    enum Screen {
        case dashboard, settings, analytics

        var title: String {
            switch self {
            case .dashboard: return "Onke"
            case .settings: return "Settings"
            case .analytics: return "Power history"
            }
        }
    }

    @Published var screen: Screen = .dashboard
}

/// The main window: a dark dashboard (yak theme) with the big signed net watts up top,
/// battery stats, per-app drain, and save-power cards. The gear flips the window content
/// to the settings pane — settings never opens a separate window.
///
/// Color logic keys off *effective charging*, never the OS flag — that distinction is
/// the whole point of the app.
struct ContentView: View {
    @ObservedObject var engine: MetricsEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: UIState
    /// Per-app drain source (phase 2). Optional so previews/tests can omit it.
    var helper: HelperClient?
    /// Phase 3 cleanup + toggles. Optional for previews/tests.
    var cleanup: CleanupCoordinator?
    var toggles: SystemToggles?
    /// Hourly in/out energy history. Optional for previews/tests.
    var ledger: EnergyLedger?

    var body: some View {
        VStack(spacing: 0) {
            header
            switch ui.screen {
            case .settings:
                SettingsView(settings: settings)
            case .analytics:
                if let ledger {
                    AnalyticsView(ledger: ledger)
                }
            case .dashboard:
                dashboard
            }
            footer
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.action)
        // Fixed-size window; OnkeApp sets .windowResizability(.contentSize).
        .frame(width: 420, height: 680)
    }

    // MARK: Header

    /// The top band: a card like every other section, sitting below the strip where the
    /// traffic lights float (the system title bar is hidden — see ``OnkeApp``). Shows
    /// the status dot, app name, live status, and the settings control.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ui.screen.title)
                    .font(.title2.weight(.semibold))
                if ui.screen == .dashboard, let s = engine.sample, s.hasBattery {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(s))
                            .frame(width: 9, height: 9)
                            .shadow(color: statusColor(s).opacity(0.5), radius: 4)
                        Text(statusText(s))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if ui.screen == .dashboard {
                if ledger != nil {
                    headerButton("clock.arrow.circlepath", help: "Power history") {
                        ui.screen = .analytics
                    }
                }
                headerButton("gearshape", help: "Settings") {
                    ui.screen = .settings
                }
            } else {
                Button {
                    ui.screen = .dashboard
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundColor(Theme.action)
                .help("Back to dashboard")
            }
        }
        .card()
        .padding(.horizontal, 26)
        .padding(.top, 14)  // the traffic lights float in this strip
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("Made with")
            Image(systemName: "heart.fill")
                .font(.caption2)
            Text("by Byteswan")
        }
        .font(.caption)
        .foregroundColor(Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .padding(.top, 2)
    }

    private func headerButton(_ symbol: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundColor(Theme.action)
        .help(help)
    }

    // MARK: Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heroCard
                statsCard
                if let helper {
                    perAppCard(helper)
                }
                if let cleanup, let toggles {
                    savePowerCard(cleanup, toggles)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
    }

    /// Big signed net watts + status line, centered so the card has no dead wing.
    /// Stroked amber when plugged-but-draining — the weak-powerbank state must read
    /// loudly.
    @ViewBuilder private var heroCard: some View {
        VStack(spacing: 6) {
            if let s = engine.sample, s.hasBattery {
                Text(String(format: "%+.1f W", s.netWatts))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(statusColor(s))
                    .contentTransition(.numericText())
                Text(s.isPluggedButDraining
                     ? "Plugged in but draining — the power source can't keep up"
                     : "net power \(s.netWatts < 0 ? "out of" : "into") the battery")
                    .font(.caption)
                    .foregroundColor(s.isPluggedButDraining ? Theme.warning : .secondary)
                // Decomposed flow where telemetry exists: what the source delivers vs.
                // what the system burns. The big number is their difference.
                if let inW = s.systemInWatts, let outW = s.systemLoadWatts {
                    HStack(spacing: 18) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(Theme.accent)
                            Text(String(format: "%.1f W in", inW))
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(Theme.draining)
                            Text(String(format: "%.1f W out", outW))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
            } else if engine.sample != nil {
                Text("No battery")
                    .font(.title.weight(.medium))
                    .foregroundColor(.secondary)
                Text("Onke monitors battery power — this Mac doesn't report one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("reading power data…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .card(highlighted: engine.sample?.isPluggedButDraining ?? false,
              tint: Theme.warning,
              fill: Theme.backgroundHighlight)
    }

    /// Battery % · time remaining · rate, as three columns.
    @ViewBuilder private var statsCard: some View {
        if let s = engine.sample, s.hasBattery {
            HStack(spacing: 0) {
                statCell(icon: batterySymbol(s.percentage),
                         value: "\(Int(s.percentage.rounded()))%",
                         label: "battery")
                Divider().frame(height: 32)
                statCell(icon: "clock",
                         value: timeRemainingValue,
                         label: timeRemainingLabel(s))
                Divider().frame(height: 32)
                statCell(icon: "gauge.with.needle",
                         value: rateValue,
                         label: "per hour")
            }
            .card()
        }
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func perAppCard(_ helper: HelperClient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Per-app drain", icon: "app.badge")
            PerAppView(helper: helper, onQuit: cleanup.map { c in { c.quit($0) } })
        }
        .card()
    }

    private func savePowerCard(_ cleanup: CleanupCoordinator, _ toggles: SystemToggles) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Save power", icon: "leaf")
            SavePowerView(cleanup: cleanup, toggles: toggles)
        }
        .card()
    }

    // MARK: Derivations

    /// Smoothed rate as "±N %", or "…" while the window warms up.
    private var rateValue: String {
        guard let rate = engine.rate.ratePercentPerHour else { return "…" }
        return String(format: "%+.0f%%", rate)
    }

    private var timeRemainingValue: String {
        guard engine.rate.isWarmedUp else { return "…" }
        guard let seconds = engine.rate.timeRemaining else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func timeRemainingLabel(_ s: PowerSample) -> String {
        s.isEffectivelyCharging ? "to full" : "left"
    }

    /// Mint when effectively charging, amber when plugged-but-draining, red on battery.
    private func statusColor(_ s: PowerSample) -> Color {
        if s.isEffectivelyCharging { return Theme.accent }
        if s.isPluggedButDraining { return Theme.warning }
        return Theme.draining
    }

    private func statusText(_ s: PowerSample) -> String {
        if s.isEffectivelyCharging { return "External · charging" }
        if s.isPluggedButDraining { return "Plugged in but draining" }
        return "On battery"
    }

    private func batterySymbol(_ pct: Double) -> String {
        switch pct {
        case ..<12.5: return "battery.0percent"
        case ..<37.5: return "battery.25percent"
        case ..<62.5: return "battery.50percent"
        case ..<87.5: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

#if DEBUG
/// A trivial preview-only provider that emits one fixed sample. The full scripted fake
/// lives in the test target; previews just need static states to render against.
private final class PreviewPowerSource: PowerSourceProviding {
    let latest: PowerSample?
    init(_ sample: PowerSample) { latest = sample }
    func start(interval: TimeInterval, onSample: @escaping (PowerSample) -> Void) {
        if let latest { onSample(latest) }
    }
    func stop() {}
}

private func previewSample(amps: Double, external: Bool) -> PowerSample {
    PowerSample(timestamp: Date(), hasBattery: true, percentage: 62,
                amperageMilliAmps: amps, voltageMilliVolts: 12_600,
                externalConnected: external, osReportsCharging: external)
}

#Preview("Discharging") {
    let engine = MetricsEngine(
        provider: PreviewPowerSource(previewSample(amps: -1800, external: false)))
    ContentView(engine: engine,
                settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!),
                ui: UIState())
        .onAppear { engine.start() }
}

#Preview("Weak powerbank") {
    let engine = MetricsEngine(
        provider: PreviewPowerSource(previewSample(amps: -400, external: true)))
    ContentView(engine: engine,
                settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!),
                ui: UIState())
        .onAppear { engine.start() }
}
#endif
