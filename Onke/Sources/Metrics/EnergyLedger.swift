import Foundation
import Combine

/// Accumulates energy in/out per *clock* hour (1 PM–2 PM, 2 PM–3 PM — absolute
/// boundaries, never relative), so you can tell how much a powerbank actually delivered
/// over an afternoon.
///
/// "In" is energy delivered by the external source (`systemInWatts` telemetry); "out"
/// is energy the system consumed (`systemLoadWatts`). On machines without telemetry it
/// falls back to the battery's signed net power split by sign. Persistence is
/// UserDefaults-only (spec §2) — the last 48 hour-buckets as a small JSON blob.
@MainActor
final class EnergyLedger: ObservableObject {

    struct HourBucket: Codable, Identifiable, Equatable {
        /// Start of the clock hour this bucket covers.
        var hourStart: Date
        var wattHoursIn: Double = 0
        var wattHoursOut: Double = 0
        var id: Date { hourStart }
    }

    @Published private(set) var buckets: [HourBucket] = []

    private let defaults: UserDefaults
    private static let key = "ledger.hourly"
    private let maxBuckets = 48
    private var lastTimestamp: Date?
    private var ingestsSincePersist = 0
    private var cancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([HourBucket].self, from: data) {
            buckets = decoded
        }
    }

    func attach(to engine: MetricsEngine, expectedInterval: TimeInterval) {
        cancellable = engine.didSample.sink { [weak self] sample, _ in
            Task { @MainActor in
                self?.ingest(sample, expectedInterval: expectedInterval)
            }
        }
    }

    /// Fold one sample into the current hour: energy = power × elapsed time since the
    /// previous sample. Sleep/wake gaps (dt far beyond the sampling cadence) are skipped
    /// rather than attributing phantom energy to hours the lid was closed.
    func ingest(_ sample: PowerSample, expectedInterval: TimeInterval) {
        guard sample.hasBattery else { return }
        defer { lastTimestamp = sample.timestamp }
        guard let last = lastTimestamp else { return }
        let dt = sample.timestamp.timeIntervalSince(last)
        guard dt > 0, dt <= expectedInterval * 4 else { return }

        let inWatts: Double
        let outWatts: Double
        if let sysIn = sample.systemInWatts, let load = sample.systemLoadWatts {
            inWatts = max(0, sysIn)
            outWatts = max(0, load)
        } else {
            inWatts = max(0, sample.netWatts)
            outWatts = max(0, -sample.netWatts)
        }
        let hours = dt / 3600.0
        add(wattHoursIn: inWatts * hours, wattHoursOut: outWatts * hours,
            at: sample.timestamp)
    }

    private func add(wattHoursIn: Double, wattHoursOut: Double, at date: Date) {
        let hourStart = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        var rolledOver = false
        if let idx = buckets.firstIndex(where: { $0.hourStart == hourStart }) {
            buckets[idx].wattHoursIn += wattHoursIn
            buckets[idx].wattHoursOut += wattHoursOut
        } else {
            buckets.append(HourBucket(hourStart: hourStart,
                                      wattHoursIn: wattHoursIn,
                                      wattHoursOut: wattHoursOut))
            buckets.sort { $0.hourStart < $1.hourStart }
            if buckets.count > maxBuckets {
                buckets.removeFirst(buckets.count - maxBuckets)
            }
            rolledOver = true
        }

        // Persist on hour rollover and roughly once a minute in between — not on every
        // 5s sample (the ledger must not become the drain it measures).
        ingestsSincePersist += 1
        if rolledOver || ingestsSincePersist >= 12 {
            persist()
            ingestsSincePersist = 0
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(buckets) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
