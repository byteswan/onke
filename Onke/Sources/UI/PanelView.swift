import SwiftUI

/// The compact always-on dashboard content (spec §5.2), hosted inside the floating
/// `NSPanel`. Top-to-bottom: big signed net watts, then battery %, then the power-source
/// status line with the loud amber "plugged in but draining" state.
///
/// Colour logic keys off *effective charging*, never the OS flag — that distinction is
/// the whole point of the app.
struct PanelView: View {
    @ObservedObject var engine: MetricsEngine
    @ObservedObject var settings: AppSettings
    /// Per-app drain source (phase 2). Optional so previews/tests can omit it.
    var helper: HelperClient?
    /// Phase 3 cleanup + toggles. Optional for previews/tests.
    var cleanup: CleanupCoordinator?
    var toggles: SystemToggles?

    /// Invoked by the gear button. Injected so the view stays decoupled from AppKit.
    var onOpenSettings: () -> Void = {}

    @State private var showPerApp = false
    @State private var showSavePower = false

    var body: some View {
        VStack(alignment: .leading, spacing: settings.collapsed ? 4 : 10) {
            header
            wattsHeadline
            if !settings.collapsed {
                batteryRow
                timeRow
                statusLine
                if helper != nil { perAppSection }
                if cleanup != nil { savePowerSection }
            }
        }
        .padding(settings.collapsed ? 10 : 16)
        .frame(width: settings.collapsed ? 150 : 260, alignment: .leading)
        .background(.ultraThinMaterial)
        .opacity(settings.panelOpacity)
    }

    @ViewBuilder private var perAppSection: some View {
        if let helper {
            Divider()
            DisclosureGroup(isExpanded: $showPerApp) {
                // In phase 3 each row gains a Quit action (guarded by the denylist).
                PerAppView(helper: helper, onQuit: cleanup.map { c in { c.quit($0) } })
                    .padding(.top, 4)
            } label: {
                Text("Per-app drain").font(.subheadline)
            }
        }
    }

    @ViewBuilder private var savePowerSection: some View {
        if let cleanup, let toggles {
            Divider()
            DisclosureGroup(isExpanded: $showSavePower) {
                SavePowerView(cleanup: cleanup, toggles: toggles)
                    .padding(.top, 4)
            } label: {
                Text("Save power").font(.subheadline)
            }
        }
    }

    // MARK: Header (gear + collapse)

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { settings.collapsed.toggle() }
            } label: {
                Image(systemName: settings.collapsed
                      ? "arrow.up.left.and.arrow.down.right"
                      : "arrow.down.right.and.arrow.up.left")
            }
            .help(settings.collapsed ? "Expand" : "Collapse")
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .help("Settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.caption)
    }

    // MARK: Sections

    @ViewBuilder private var wattsHeadline: some View {
        if let s = engine.sample, s.hasBattery {
            Text(wattsText(s.netWatts))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(wattsColor(s))
                .contentTransition(.numericText())
        } else if let s = engine.sample, !s.hasBattery {
            Text("No battery")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var batteryRow: some View {
        if let s = engine.sample, s.hasBattery {
            HStack(spacing: 6) {
                Image(systemName: batterySymbol(s.percentage))
                    .foregroundStyle(.secondary)
                Text("\(Int(s.percentage.rounded()))%")
                    .font(.headline)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(rateText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var timeRow: some View {
        if let s = engine.sample, s.hasBattery {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(timeRemainingText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let s = engine.sample, s.hasBattery {
            HStack(spacing: 6) {
                Circle()
                    .fill(wattsColor(s))
                    .frame(width: 8, height: 8)
                Text(statusText(s))
                    .font(.subheadline)
                    .foregroundStyle(s.isPluggedButDraining ? .primary : .secondary)
            }
            .padding(.vertical, s.isPluggedButDraining ? 4 : 0)
            .padding(.horizontal, s.isPluggedButDraining ? 8 : 0)
            .background(
                s.isPluggedButDraining
                    ? RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.22))
                    : nil
            )
        }
    }

    // MARK: Derivations

    private func wattsText(_ watts: Double) -> String {
        String(format: "%+.1f W", watts)
    }

    /// Smoothed rate as "±N %/hr", or "calculating…" while the window warms up.
    private var rateText: String {
        guard let rate = engine.rate.ratePercentPerHour else { return "calculating…" }
        return String(format: "%+.0f %%/hr", rate)
    }

    /// Time-to-empty or time-to-full, whichever applies, as "Nh Mm left / to full".
    /// Shows "calculating…" until warm, or "—" when a finite time doesn't apply
    /// (e.g. full on AC with amperage ~0).
    private var timeRemainingText: String {
        guard engine.rate.isWarmedUp else { return "calculating…" }
        guard let seconds = engine.rate.timeRemaining else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let clock = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let charging = engine.sample?.isEffectivelyCharging ?? false
        return charging ? "\(clock) to full" : "\(clock) left"
    }

    /// Green when effectively charging, amber when plugged-but-draining, red when on
    /// battery. The amber case is the weak-powerbank warning and must read loudly.
    private func wattsColor(_ s: PowerSample) -> Color {
        if s.isEffectivelyCharging { return .green }
        if s.isPluggedButDraining { return .orange }
        return .red
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
    PanelView(engine: engine, settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!))
        .onAppear { engine.start() }
}

#Preview("Weak powerbank") {
    let engine = MetricsEngine(
        provider: PreviewPowerSource(previewSample(amps: -400, external: true)))
    PanelView(engine: engine, settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!))
        .onAppear { engine.start() }
}
#endif
