import SwiftUI

/// The compact always-on dashboard content (spec §5.2), hosted inside the floating
/// `NSPanel`. Top-to-bottom: big signed net watts, then battery %, then the power-source
/// status line with the loud amber "plugged in but draining" state.
///
/// Colour logic keys off *effective charging*, never the OS flag — that distinction is
/// the whole point of the app.
struct PanelView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            wattsHeadline
            batteryRow
            statusLine
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(.ultraThinMaterial)
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

#Preview("Discharging") {
    let engine = MetricsEngine(provider: FakePowerSource(scenario: .discharge))
    PanelView(engine: engine).onAppear { engine.start() }
}

#Preview("Weak powerbank") {
    let engine = MetricsEngine(provider: FakePowerSource(scenario: .weakPowerbank))
    PanelView(engine: engine).onAppear { engine.start() }
}
