import SwiftUI

/// Onke's visual theme, borrowed from the yak mac app: forced dark, #121212 background,
/// mint accent, and card sections (subtle gray fill + stroked rounded rect). Colors are
/// defined in code rather than an asset catalog since the app is dark-only.
enum Theme {
    /// Window background (#121212).
    static let background = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
    /// Faint teal-green tinge used behind the hero card (#012722 @ 20%).
    static let backgroundHighlight = Color(red: 0x01 / 255, green: 0x27 / 255, blue: 0x22 / 255)
        .opacity(0.2)
    /// Primary accent — a darkened take on yak's CustomMint (#03866E; the original is
    /// #04A78A). Also the "charging" color.
    static let accent = Color(red: 0x03 / 255, green: 0x86 / 255, blue: 0x6E / 255)
    /// Interactive accent — anything this color can be pressed (buttons, links,
    /// toggles). Currently the same mint as `accent`; swap here to re-color every
    /// control at once.
    static let action = accent
    /// The loud weak-powerbank warning color.
    static let warning = Color.orange
    /// Discharging.
    static let draining = Color.red

    // MARK: Surfaces & text

    /// Card fill and stroke — every boxed section uses these, including the header.
    static let cardFill = Color.gray.opacity(0.1)
    static let cardStroke = Color.gray.opacity(0.3)
    /// Section heading text.
    static let sectionHeading = Color.primary
}

extension View {
    /// Yak-style card: gray fill, rounded rect, subtle stroke — accent-tinted when
    /// highlighted (used for the loud plugged-but-draining state). An optional extra
    /// `fill` is layered over the base so tinges cover the whole card edge-to-edge.
    func card(highlighted: Bool = false, tint: Color = Theme.accent,
              fill: Color? = nil) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.cardFill)
                    if let fill {
                        RoundedRectangle(cornerRadius: 8).fill(fill)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(highlighted ? tint.opacity(0.5) : Theme.cardStroke,
                            lineWidth: 1)
            )
    }
}

/// Shared back button used by both the Settings and Power-history screens (chevron +
/// "Back"). Font is bumped 20% over the default subheadline so the affordance reads
/// clearly. A single component keeps the two screens' back buttons identical.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                Text(Strings.Dashboard.back)
            }
            // subheadline ≈ 15pt; +20% ≈ 18pt.
            .font(.system(size: 18, weight: .medium))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundColor(Theme.action)
        .help(Strings.Dashboard.backToDashboardHelp)
    }
}

/// A small ⓘ button that pops an explanation of exactly what the neighboring control
/// does when pressed. Click to open; also available on hover via the tooltip.
struct InfoTip: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}

/// A tappable card header that expands/collapses its body: `SectionHeader` on the left,
/// an optional ⓘ tip, and a chevron that rotates 90° when open. Used for the dashboard's
/// Per-app / Save-power cards and the Power-history day cards.
struct CollapsibleCardHeader: View {
    let title: String
    let icon: String
    var tip: String? = nil
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                SectionHeader(title: title, icon: icon)
                if let tip {
                    InfoTip(text: tip)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

/// Quiet section title: icon + label. Deliberately not a filled chip — filled shapes
/// read as pressable.
struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.headline)
        .foregroundColor(Theme.sectionHeading)
    }
}
