import SwiftUI

/// The expandable per-app energy section (spec §6.2). Shows the top processes by energy
/// impact once the privileged helper is approved; otherwise a "requires helper" explainer
/// with a retry/approve button. Energy values are relative and unitless — the column is
/// labeled "Energy impact", never watts.
struct PerAppView: View {
    @ObservedObject var helper: HelperClient
    /// Phase 3 injects a per-row Quit action here; nil hides the affordance.
    var onQuit: ((AppEnergy) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy impact")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            switch helper.state {
            case .enabled:
                appList
            case .notRegistered, .requiresApproval, .failed:
                explainer
            }
        }
    }

    @ViewBuilder private var appList: some View {
        if helper.topApps.isEmpty {
            Text("Measuring…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let maxImpact = helper.topApps.map(\.energyImpact).max() ?? 1
            ForEach(helper.topApps) { app in
                AppRow(app: app, fraction: maxImpact > 0 ? app.energyImpact / maxImpact : 0,
                       onQuit: onQuit)
            }
        }
    }

    @ViewBuilder private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(explainerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(explainerButtonTitle) { helper.enable() }
                if case .requiresApproval = helper.state {
                    Button("Open Settings") { helper.openApprovalSettings() }
                }
            }
            .controlSize(.small)
        }
    }

    private var explainerText: String {
        switch helper.state {
        case .requiresApproval:
            return "Per-app drain needs the Onke helper. Approve it in System Settings, then retry."
        case .failed(let msg):
            return "Couldn't start the helper: \(msg)"
        default:
            return "Per-app drain uses a small privileged helper to read powermetrics. It's off by default."
        }
    }

    private var explainerButtonTitle: String {
        if case .requiresApproval = helper.state { return "Retry" }
        return "Enable per-app drain"
    }
}

/// A single app's row: icon, name, a relative energy bar, and the numeric impact.
private struct AppRow: View {
    let app: AppEnergy
    let fraction: Double
    var onQuit: ((AppEnergy) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed").frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
            Text(app.name).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            GeometryReader { geo in
                Capsule()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: max(2, geo.size.width * fraction), height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 40, height: 12)
            Text(String(format: "%.0f", app.energyImpact))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let onQuit {
                Button {
                    onQuit(app)
                } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Quit \(app.name)")
            }
        }
    }
}
