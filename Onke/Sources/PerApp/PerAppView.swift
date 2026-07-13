import SwiftUI

/// The expandable per-app energy section (spec §6.2). Shows the top processes by energy
/// impact once the privileged helper is approved; otherwise a "requires helper" explainer
/// with a retry/approve button. Energy values are relative and unitless — the column is
/// labeled "Energy impact", never watts.
struct PerAppView: View {
    @ObservedObject var helper: HelperClient
    /// Phase 3 injects a per-row Quit action here; nil hides the affordance.
    var onQuit: ((AppEnergy) -> Void)?
    /// When false (default), system processes/daemons are hidden — only user apps show.
    var showSystem: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch helper.state {
            case .enabled:
                appList
            case .notRegistered, .requiresApproval, .failed:
                explainer
            }
        }
    }

    private var visibleApps: [AppEnergy] {
        showSystem ? helper.topApps : helper.topApps.filter { !ProcessCatalog.isCritical($0) }
    }

    @ViewBuilder private var appList: some View {
        let apps = visibleApps
        if helper.topApps.isEmpty {
            Text(Strings.PerApp.measuring)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if apps.isEmpty {
            // Everything measured was a system process and the filter is on.
            Text(Strings.PerApp.onlySystemHidden)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Scale bars against the visible set so the top visible row fills the bar.
            let maxImpact = apps.map(\.energyImpact).max() ?? 1
            ForEach(apps) { app in
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
                // Raw error strings are developer noise; keep them one hover away.
                .help(explainerDetail ?? "")
            HStack {
                Button(explainerButtonTitle) { helper.enable() }
                    .buttonStyle(.borderedProminent)
                    .focusable(false)
                if case .requiresApproval = helper.state {
                    Button(Strings.PerApp.openSettings) { helper.openApprovalSettings() }
                }
            }
            .controlSize(.small)
        }
    }

    private var explainerText: String {
        switch helper.state {
        case .requiresApproval:
            return Strings.PerApp.requiresApproval
        case .failed:
            return Strings.PerApp.failed
        default:
            return Strings.PerApp.offByDefault
        }
    }

    private var explainerDetail: String? {
        if case .failed(let msg) = helper.state { return msg }
        return nil
    }

    private var explainerButtonTitle: String {
        if case .requiresApproval = helper.state { return Strings.PerApp.retry }
        return Strings.PerApp.enable
    }
}

/// A single app's row: icon, name, a relative energy bar, and the numeric impact.
private struct AppRow: View {
    let app: AppEnergy
    let fraction: Double
    var onQuit: ((AppEnergy) -> Void)?

    /// Critical processes (daemons / system) are locked and can't be quit here.
    private var isCritical: Bool { ProcessCatalog.isCritical(app) }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: isCritical ? "gearshape.2" : "app.dashed")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.caption).lineLimit(1)
                    .textSelection(.enabled)
                if let desc = ProcessCatalog.describe(app) {
                    Text(desc).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
            GeometryReader { geo in
                // Data viz, not a control — mint, never the interactive blue.
                Capsule()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: max(2, geo.size.width * fraction), height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 40, height: 12)
            Text(String(format: "%.0f", app.energyImpact))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            // `isCritical` is the single lock authority: critical → 🔒 (no Quit),
            // non-critical → Quit button. No secondary gate, so a non-critical row always
            // shows its control.
            if isCritical {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(Strings.PerApp.systemProtectedHelp)
            } else if let onQuit {
                Button {
                    onQuit(app)
                } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(Strings.PerApp.quitHelp(app: app.name))
            }
        }
    }
}
