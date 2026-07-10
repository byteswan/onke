import SwiftUI

/// The "Power history" screen: a per-clock-hour table of energy in (delivered by the
/// charger/powerbank) and energy out (consumed by the system), newest first, grouped by
/// day. This is how you tell how much a powerbank actually gave you over an afternoon.
struct AnalyticsView: View {
    @ObservedObject var ledger: EnergyLedger

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if ledger.buckets.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: group.title, icon: "calendar")
                            hourTable(group.rows)
                        }
                        .card()
                    }
                }
                Text("In = energy drawn from the charger or powerbank. Out = energy the system consumed. Hours are clock hours (1300 – 1400), so totals line up with your watch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Power history", icon: "clock.arrow.circlepath")
            Text("No history yet — Onke records energy in/out per clock hour while it runs. Check back after an hour.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Table

    private func hourTable(_ rows: [EnergyLedger.HourBucket]) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Hour")
                Spacer()
                Text("In (Wh)").frame(width: 70, alignment: .trailing)
                Text("Out (Wh)").frame(width: 70, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)

            Divider()

            ForEach(rows) { bucket in
                HStack {
                    Text(hourLabel(bucket.hourStart))
                        .font(.callout)
                    Spacer()
                    Text(String(format: "%.1f", bucket.wattHoursIn))
                        .foregroundColor(Theme.accent)
                        .frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.1f", bucket.wattHoursOut))
                        .foregroundColor(Theme.draining)
                        .frame(width: 70, alignment: .trailing)
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
