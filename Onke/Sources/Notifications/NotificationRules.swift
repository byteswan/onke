import Foundation

/// A notification the engine wants to post: a stable identifier (so the OS coalesces
/// repeats) plus title/body copy.
struct PowerNotification: Equatable {
    var id: String
    var title: String
    var body: String
}

/// Everything a rule needs to decide, assembled fresh each sample by the engine. Keeping
/// rules pure functions of this context (no direct clock / OS access) is what makes the
/// hysteresis logic unit-testable — spec §5.5 requires proving notifications don't
/// repeat-spam at a threshold.
struct RuleContext {
    var sample: PowerSample
    var rate: RateEstimator.Output
    /// Rolling 10-min average of watts-out (positive magnitude), for the drain-spike rule.
    var avgWattsOut: Double
    /// How long the current spike/weak condition has been continuously true, in seconds.
    var sustainedSpike: TimeInterval
    var sustainedWeak: TimeInterval
    var now: Date

    // Tunables sourced from settings.
    var timeLowMinutes: Double
    var timeLowRearmMinutes: Double
    var drainSpikeMultiplier: Double
}

/// A single notification rule with its own hysteresis state. `evaluate` returns a
/// notification to post on a fresh downward crossing, and `nil` otherwise; the rule
/// re-arms itself only once the value recovers past the buffer (spec §5.3).
protocol NotificationRule: AnyObject {
    func evaluate(_ ctx: RuleContext) -> PowerNotification?
}

// MARK: Rule 1 — Time remaining low

/// Fires when computed time-to-empty < `timeLowMinutes` while discharging and warmed up.
/// Re-arms only when time-to-empty recovers > `timeLowRearmMinutes` or charging begins.
final class TimeRemainingLowRule: NotificationRule {
    private var armed = true

    func evaluate(_ ctx: RuleContext) -> PowerNotification? {
        let s = ctx.sample
        if s.isEffectivelyCharging {
            armed = true            // charging always re-arms
            return nil
        }
        guard ctx.rate.isWarmedUp, s.amperageMilliAmps < 0,
              let seconds = ctx.rate.timeRemaining else { return nil }
        let minutes = seconds / 60

        if minutes > ctx.timeLowRearmMinutes { armed = true }

        guard armed, minutes < ctx.timeLowMinutes else { return nil }
        armed = false
        return PowerNotification(
            id: "time-low",
            title: Strings.Notifications.timeLowTitle,
            body: Strings.Notifications.timeLowBody(minutes: Int(minutes)))
    }
}

// MARK: Rule 2 — Drain spike

/// Fires when smoothed watts-out exceeds `multiplier`× the 10-min average, sustained
/// ≥ 60s. Re-arms when it drops back under 1.2× average. The engine fills in the top
/// offender name (phase 2); phase 1 copy is generic.
final class DrainSpikeRule: NotificationRule {
    private var armed = true
    var topOffender: String?    // set by engine once per-app data exists (phase 2)

    func evaluate(_ ctx: RuleContext) -> PowerNotification? {
        guard ctx.avgWattsOut > 0.01 else { return nil }
        let wattsOut = max(0, -ctx.sample.netWatts)
        let ratio = wattsOut / ctx.avgWattsOut

        if ratio < 1.2 { armed = true }

        guard armed, ratio >= ctx.drainSpikeMultiplier, ctx.sustainedSpike >= 60 else { return nil }
        armed = false
        return PowerNotification(
            id: "drain-spike",
            title: Strings.Notifications.drainSpikeTitle,
            body: Strings.Notifications.drainSpikeBody(watts: wattsOut, topOffender: topOffender))
    }
}

// MARK: Rule 3 — Powerbank too weak

/// Fires when external is connected but net amperage < 0, sustained ≥ 60s (the weak
/// powerbank). Re-arms on effective charging or unplug.
final class WeakPowerbankRule: NotificationRule {
    private var armed = true

    func evaluate(_ ctx: RuleContext) -> PowerNotification? {
        let s = ctx.sample
        if s.isEffectivelyCharging || !s.externalConnected {
            armed = true
            return nil
        }
        guard armed, s.isPluggedButDraining, ctx.sustainedWeak >= 60 else { return nil }
        armed = false
        return PowerNotification(
            id: "weak-powerbank",
            title: Strings.Notifications.weakPowerbankTitle,
            body: Strings.Notifications.weakPowerbankBody(watts: s.netWatts))
    }
}

// MARK: Rule 4 — Unplug the powerbank

/// Fires when external is connected and the battery is full (≥ 100% or charging stopped
/// at full). Re-arms on unplug.
final class UnplugAtFullRule: NotificationRule {
    private var armed = true

    func evaluate(_ ctx: RuleContext) -> PowerNotification? {
        let s = ctx.sample
        guard s.externalConnected else { armed = true; return nil }
        let full = s.percentage >= 100 || (s.osReportsCharging == false && s.amperageMilliAmps <= 0 && s.percentage >= 99)
        guard armed, full else { return nil }
        armed = false
        return PowerNotification(
            id: "unplug-full",
            title: Strings.Notifications.unplugFullTitle,
            body: Strings.Notifications.unplugFullBody)
    }
}

// MARK: Rule 5 — Level warnings

/// Fires once as the level crosses each of 70/50/25/10 while discharging. All thresholds
/// reset (re-arm) once charged back above 75%.
final class LevelWarningRule: NotificationRule {
    private let thresholds: [Double] = [70, 50, 25, 10]
    private var fired: Set<Double> = []
    private var lastPercentage: Double?

    func evaluate(_ ctx: RuleContext) -> PowerNotification? {
        let s = ctx.sample
        defer { lastPercentage = s.percentage }

        if s.percentage > 75 { fired.removeAll() }   // recovered — re-arm every level

        guard s.amperageMilliAmps < 0, let prev = lastPercentage else { return nil }

        // Find a threshold we crossed downward this tick and haven't fired yet.
        for t in thresholds where !fired.contains(t) && prev > t && s.percentage <= t {
            fired.insert(t)
            return PowerNotification(
                id: "level-\(Int(t))",
                title: Strings.Notifications.levelTitle(percent: Int(t)),
                body: Strings.Notifications.levelBody(threshold: t))
        }
        return nil
    }
}
