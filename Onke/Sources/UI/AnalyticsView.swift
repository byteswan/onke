import SwiftUI

/// The "Power history" screen: a per-clock-hour table of energy in (delivered by the
/// charger/powerbank) and energy out (consumed by the system), newest first, grouped by
/// day. This is how you tell how much a powerbank actually gave you over an afternoon.
struct AnalyticsView: View {
    @ObservedObject var ledger: EnergyLedger
    /// Which day cards are expanded. Empty by default, so every day starts collapsed and
    /// only opens when tapped.
    @State private var expandedDays: Set<Date> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if ledger.buckets.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.day) { group in
                        dayCard(group)
                    }
                }
                Text(Strings.Analytics.footnote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
    }

    /// One collapsible day: a tappable header (calendar + date + chevron) that toggles
    /// the hour table below it. Collapsed by default.
    private func dayCard(_ group: (day: Date, title: String, rows: [EnergyLedger.HourBucket])) -> some View {
        let isExpanded = expandedDays.contains(group.day)
        return VStack(alignment: .leading, spacing: 8) {
            CollapsibleCardHeader(title: group.title, icon: "calendar",
                                  isExpanded: isExpanded) {
                if isExpanded { expandedDays.remove(group.day) }
                else { expandedDays.insert(group.day) }
            }
            if isExpanded {
                hourTable(group.rows)
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: Strings.Analytics.emptyTitle, icon: "clock.arrow.circlepath")
            Text(Strings.Analytics.emptyBody)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Table

    private func hourTable(_ rows: [EnergyLedger.HourBucket]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(Strings.Analytics.hourColumn)
                Spacer()
                Text(Strings.Analytics.inOutColumn).frame(width: 90, alignment: .trailing)
                HStack(spacing: 2) {
                    Text(Strings.Analytics.inMahColumn)
                    InfoTip(text: Strings.Analytics.mahTip)
                }.frame(width: 74, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)

            Divider()

            ForEach(rows) { bucket in
                HStack(spacing: 4) {
                    Text(hourLabel(bucket.hourStart))
                        .font(.callout)
                    Spacer()
                    // Merged In / Out: two numbers, each keeping its own color.
                    HStack(spacing: 2) {
                        Text(String(format: "%.1f", bucket.wattHoursIn))
                            .foregroundColor(Theme.accent)
                        Text("/").foregroundColor(.secondary)
                        Text(String(format: "%.1f", bucket.wattHoursOut))
                            .foregroundColor(Theme.draining)
                    }
                    .frame(width: 90, alignment: .trailing)
                    Text(String(format: "%.0f", Strings.Analytics.mAh(fromWattHours: bucket.wattHoursIn)))
                        .foregroundColor(Theme.accent)
                        .frame(width: 74, alignment: .trailing)
                }
                .font(.callout.monospacedDigit())
            }
        }
    }

    // MARK: Grouping & formatting

    /// Buckets grouped by calendar day, newest day and newest hour first.
    private var days: [(day: Date, title: String, rows: [EnergyLedger.HourBucket])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: ledger.buckets) {
            calendar.startOfDay(for: $0.hourStart)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day: day,
             title: Self.dayFormatter.string(from: day),
             rows: grouped[day]!.sorted { $0.hourStart > $1.hourStart })
        }
    }

    private func hourLabel(_ start: Date) -> String {
        let end = start.addingTimeInterval(3600)
        return "\(Self.hourFormatter.string(from: start)) – \(Self.hourFormatter.string(from: end))"
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"  // 24-hour, "0200", "1300"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true  // "Today", "Yesterday"
        return f
    }()
}
