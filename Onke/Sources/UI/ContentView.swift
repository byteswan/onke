import SwiftUI

/// Transient UI state shared between the main window and the menu bar extra (which
/// screen the window shows). Not persisted.
@MainActor
final class UIState: ObservableObject {
    enum Screen {
        case dashboard, settings, analytics

        var title: String {
            switch self {
            case .dashboard: return Strings.App.name
            case .settings: return Strings.App.settingsTitle
            case .analytics: return Strings.App.analyticsTitle
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

    /// Which of the two tall dashboard cards is expanded. Only one at a time — the window
    /// is fixed-height, so opening one collapses the other. Both start collapsed.
    private enum ExpandableCard { case none, perApp, savePower }
    @State private var expandedCard: ExpandableCard = .perApp

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
                    headerButton("clock.arrow.circlepath", help: Strings.Dashboard.powerHistoryHelp) {
                        ui.screen = .analytics
                    }
                }
                headerButton("gearshape", help: Strings.Dashboard.settingsHelp) {
                    ui.screen = .settings
                }
            } else {
                BackButton { ui.screen = .dashboard }
            }
        }
        .card()
        .padding(.horizontal, 26)
        .padding(.top, 14)  // the traffic lights float in this strip
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(Strings.App.madeWithPrefix)
            Image(systemName: "heart.fill")
                .font(.caption2)
            Text(Strings.App.madeWithSuffix)
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

    /// No outer scroll: the hero + stats sit fixed at the top, and whichever card is
    /// expanded flexes to fill the remaining height and scrolls *internally* if its
    /// content overflows. A trailing spacer keeps everything top-aligned when both
    /// cards are collapsed.
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroCard
            statsCard
            if let helper {
                perAppCard(helper)
            }
            if let cleanup, let toggles {
                savePowerCard(cleanup, toggles)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    /// Big signed net watts + status line, centered so the card has no dead wing.
    /// Stroked amber when plugged-but-draining — the weak-powerbank state must read
    /// loudly.
    @ViewBuilder private var heroCard: some View {
        VStack(spacing: 6) {
            if let s = engine.sample, s.hasBattery {
                if isFullAndCharging(s) {
                    // Special case: topped off on external power. The raw net reads ~0 W,
                    // which would otherwise show as a red "+0.0 W". Say it plainly instead.
                    Text(Strings.Dashboard.batteryFullCharging)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.accent)
                        .multilineTextAlignment(.center)
                } else {
                    Text(String(format: "%+.1f W", s.netWatts))
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(statusColor(s))
                        .contentTransition(.numericText())
                    Text(s.isPluggedButDraining
                         ? Strings.Dashboard.pluggedButDraining
                         : Strings.Dashboard.netPowerDirection(draining: s.netWatts < 0))
                        .font(.caption)
                        .foregroundColor(s.isPluggedButDraining ? Theme.warning : .secondary)
                }
                // Decomposed flow where telemetry exists: what the source delivers vs.
                // what the system burns. The big number is their difference.
                if let inW = s.systemInWatts, let outW = s.systemLoadWatts {
                    HStack(spacing: 18) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(Theme.accent)
                            Text(Strings.Dashboard.wattsIn(inW))
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(Theme.draining)
                            Text(Strings.Dashboard.wattsOut(outW))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                // Charging-source line: shown whenever an adapter is connected. Name +
                // wattage on the face; every reported field lives in the ⓘ tip.
                if s.externalConnected, let adapter = engine.adapter {
                    HStack(spacing: 4) {
                        Image(systemName: adapter.isWireless ? "wave.3.right.circle" : "powerplug")
                            .foregroundColor(.secondary)
                        Text(Strings.Dashboard.adapterLine(adapter))
                            .lineLimit(1).truncationMode(.middle)
                        InfoTip(text: Strings.Dashboard.adapterDetail(adapter))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            } else if engine.sample != nil {
                Text(Strings.Dashboard.noBattery)
                    .font(.title.weight(.medium))
                    .foregroundColor(.secondary)
                Text(Strings.Dashboard.noBatteryDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text(Strings.Dashboard.readingPowerData)
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
                         label: Strings.Dashboard.batteryLabel)
                Divider().frame(height: 32)
                statCell(icon: "clock",
                         value: timeRemainingValue,
                         label: timeRemainingLabel(s))
                Divider().frame(height: 32)
                statCell(icon: "gauge.with.needle",
                         value: rateValue,
                         label: Strings.Dashboard.perHourLabel)
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
            CollapsibleCardHeader(title: Strings.Dashboard.perAppDrainTitle,
                                  icon: "app.badge",
                                  tip: Strings.Dashboard.energyImpactTip,
                                  isExpanded: expandedCard == .perApp) {
                toggleCard(.perApp)
            }
            if expandedCard == .perApp {
                cardScroll {
                    PerAppView(helper: helper,
                               onQuit: cleanup.map { c in { c.quit($0) } },
                               showSystem: settings.showSystemProcesses)
                }
            }
        }
        .card()
    }

    private func savePowerCard(_ cleanup: CleanupCoordinator, _ toggles: SystemToggles) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CollapsibleCardHeader(title: Strings.Dashboard.savePowerTitle,
                                  icon: "leaf",
                                  isExpanded: expandedCard == .savePower) {
                toggleCard(.savePower)
            }
            if expandedCard == .savePower {
                cardScroll {
                    SavePowerView(cleanup: cleanup, toggles: toggles)
                }
            }
        }
        .card()
    }

    /// Wraps an expanded card's body so it scrolls *inside* the card when its content is
    /// taller than the space available — keeping the scroll bar in the card, not on the
    /// whole window. Capped so the footer stays visible. Trailing padding keeps the
    /// overlay scroll bar clear of the row controls (e.g. the ✕ quit button); top padding
    /// separates the list from the card header.
    private func cardScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 20)
                .padding(.top, 4)
        }
        .frame(maxHeight: 360)
    }

    /// Expand the tapped card, or collapse it if it was already open. Because only one
    /// value can be held, expanding one card auto-collapses the other.
    private func toggleCard(_ card: ExpandableCard) {
        expandedCard = (expandedCard == card) ? .none : card
    }

    // MARK: Derivations

    /// Smoothed rate as "±N %", "…" while the window warms up, or "—" when the rate is
    /// too flat to be meaningful (same "—" the time-remaining column shows in that case,
    /// instead of a misleading "+0%").
    private var rateValue: String {
        guard engine.rate.isWarmedUp else { return "…" }
        guard let rate = engine.rate.ratePercentPerHour, engine.rate.timeRemaining != nil else {
            return "—"
        }
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
        s.isEffectivelyCharging ? Strings.Dashboard.toFullLabel : Strings.Dashboard.leftLabel
    }

    /// Plugged in and holding steady: external connected with essentially no current
    /// flowing (amperage ≈ 0). Happens at a full battery, and also when macOS pauses
    /// charging for battery health (e.g. at 80%). This is neither charging nor draining —
    /// without a case for it the status falls through to red "On battery", which is wrong.
    private func isPluggedAndHolding(_ s: PowerSample) -> Bool {
        s.externalConnected && abs(s.netWatts) < 0.5
    }

    /// The stricter, full-battery form used for the hero's "Fully Charged" copy.
    private func isFullAndCharging(_ s: PowerSample) -> Bool {
        isPluggedAndHolding(s) && s.percentage >= 100
    }

    /// Mint when charging or plugged-and-holding, amber when plugged-but-draining, red
    /// only when actually on battery and draining.
    private func statusColor(_ s: PowerSample) -> Color {
        if s.isEffectivelyCharging || isPluggedAndHolding(s) { return Theme.accent }
        if s.isPluggedButDraining { return Theme.warning }
        return Theme.draining
    }

    private func statusText(_ s: PowerSample) -> String {
        if isFullAndCharging(s) { return Strings.Dashboard.statusCharged }
        if s.isEffectivelyCharging { return Strings.Dashboard.statusCharging }
        if isPluggedAndHolding(s) { return Strings.Dashboard.statusPluggedHolding }
        if s.isPluggedButDraining { return Strings.Dashboard.statusPluggedDraining }
        return Strings.Dashboard.statusOnBattery
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
