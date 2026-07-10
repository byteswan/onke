import Foundation

/// Smoothed charge/discharge rate and time-remaining, computed by the app from capacity
/// deltas — deliberately NOT trusting macOS's own time-remaining estimate (spec §5.1).
///
/// Each sample contributes an instantaneous `%/hr` derived from the percentage change
/// since the previous sample. That instantaneous rate is folded into an exponential
/// moving average whose smoothing constant is chosen so the EMA has a ~5-minute time
/// constant regardless of the sampling interval. Time-to-empty / time-to-full then falls
/// out of the smoothed rate.
///
/// Pure and side-effect-free (no timer, no I/O) so it can be unit-tested by feeding a
/// scripted sequence of samples.
struct RateEstimator {

    /// The estimator's current view of the world, recomputed on every `ingest`.
    struct Output: Equatable {
        /// Smoothed rate in percent-per-hour. Signed: negative = draining, positive =
        /// charging. `nil` until the window has warmed up.
        var ratePercentPerHour: Double?
        /// Time until the battery hits empty (while draining) or full (while charging).
        /// `nil` when not applicable (e.g. rate ~0) or not yet warmed up.
        var timeRemaining: TimeInterval?
        /// True once enough time has elapsed for the smoothed rate to be trustworthy.
        var isWarmedUp: Bool
    }

    /// Time constant of the moving average (spec: "~5 min span").
    private let tau: TimeInterval = 300
    /// Minimum span of samples before the rate is considered trustworthy (spec: "≥ 2 min").
    private let warmupDuration: TimeInterval = 120
    /// A wall-clock jump larger than this (relative to the gap we'd expect) means the
    /// machine slept; the window is stale and must be reset (spec §5.1).
    private let sleepGapMultiplier: Double = 2.0
    private let expectedInterval: TimeInterval

    private var ema: Double?
    private var last: (time: Date, percentage: Double)?
    private var accumulatedSpan: TimeInterval = 0

    init(expectedInterval: TimeInterval = 5) {
        self.expectedInterval = expectedInterval
    }

    /// Fold a new sample in and return the updated estimate.
    mutating func ingest(_ sample: PowerSample) -> Output {
        guard sample.hasBattery else {
            reset()
            return Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: false)
        }

        defer { last = (sample.timestamp, sample.percentage) }

        guard let previous = last else {
            // First sample: nothing to diff against yet.
            return currentOutput(sample: sample)
        }

        let dt = sample.timestamp.timeIntervalSince(previous.time)

        // Non-positive or implausibly large gaps mean a clock jump / sleep-wake — the
        // rolling window is meaningless across that boundary, so start fresh.
        if dt <= 0 || dt > expectedInterval * sleepGapMultiplier {
            reset()
            return Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: false)
        }

        let instantaneousRate = (sample.percentage - previous.percentage) / dt * 3600.0

        // EMA weight derived from dt so the time constant stays ~tau regardless of the
        // actual gap between samples: alpha = 1 - e^(-dt/tau).
        let alpha = 1 - exp(-dt / tau)
        ema = ema.map { $0 + alpha * (instantaneousRate - $0) } ?? instantaneousRate
        accumulatedSpan += dt

        return currentOutput(sample: sample)
    }

    /// Drop all state — used on sleep/wake gaps and when the battery disappears.
    mutating func reset() {
        ema = nil
        last = nil
        accumulatedSpan = 0
    }

    // MARK: Derivation

    private func currentOutput(sample: PowerSample) -> Output {
        let warm = accumulatedSpan >= warmupDuration
        guard warm, let rate = ema else {
            return Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: warm)
        }
        return Output(
            ratePercentPerHour: rate,
            timeRemaining: timeRemaining(from: rate, percentage: sample.percentage),
            isWarmedUp: true
        )
    }

    /// Hours-to-boundary = distance-to-boundary(%) / |rate|(%/hr), in seconds.
    /// Below a small deadband the rate is treated as flat (e.g. full on AC, amperage ~0)
    /// and no finite time is reported.
    private func timeRemaining(from rate: Double, percentage: Double) -> TimeInterval? {
        let deadband = 0.1   // %/hr
        guard abs(rate) > deadband else { return nil }
        let distancePercent = rate < 0 ? percentage : (100 - percentage)
        guard distancePercent > 0 else { return nil }
        let hours = distancePercent / abs(rate)
        return hours * 3600.0
    }
}
