import XCTest
@testable import Onke

/// Exercises the five §5.3 rules, with emphasis on hysteresis — spec §5.5 requires
/// proving a value hovering at a threshold fires once, not repeatedly.
final class NotificationRulesTests: XCTestCase {

    private func sample(pct: Double, amps: Double, external: Bool = false,
                        osCharging: Bool = false) -> PowerSample {
        PowerSample(timestamp: Date(), hasBattery: true, percentage: pct,
                    amperageMilliAmps: amps, voltageMilliVolts: 12_600,
                    externalConnected: external, osReportsCharging: osCharging)
    }

    private func warmRate(minutesRemaining: Double, ratePerHour: Double = -60)
        -> RateEstimator.Output {
        RateEstimator.Output(ratePercentPerHour: ratePerHour,
                             timeRemaining: minutesRemaining * 60,
                             isWarmedUp: true)
    }

    private func ctx(_ s: PowerSample, rate: RateEstimator.Output,
                     avgWattsOut: Double = 0, sustainedSpike: TimeInterval = 0,
                     sustainedWeak: TimeInterval = 0,
                     timeLow: Double = 90, rearm: Double = 110,
                     spikeMult: Double = 1.5) -> RuleContext {
        RuleContext(sample: s, rate: rate, avgWattsOut: avgWattsOut,
                    sustainedSpike: sustainedSpike, sustainedWeak: sustainedWeak,
                    now: Date(), timeLowMinutes: timeLow,
                    timeLowRearmMinutes: rearm, drainSpikeMultiplier: spikeMult)
    }

    // MARK: Rule 1 — time low + hysteresis (the anti-spam acceptance case)

    func testTimeLowFiresOnceThenHoldsUntilRecovery() {
        let rule = TimeRemainingLowRule()
        let low = sample(pct: 20, amps: -1800)

        // First crossing below 90 min fires.
        XCTAssertNotNil(rule.evaluate(ctx(low, rate: warmRate(minutesRemaining: 85))))
        // Still below (even oscillating up to 95, under the 110 re-arm buffer): silent.
        XCTAssertNil(rule.evaluate(ctx(low, rate: warmRate(minutesRemaining: 88))))
        XCTAssertNil(rule.evaluate(ctx(low, rate: warmRate(minutesRemaining: 95))))
        // Recover past the buffer, then drop again → fires again.
        XCTAssertNil(rule.evaluate(ctx(low, rate: warmRate(minutesRemaining: 115))))
        XCTAssertNotNil(rule.evaluate(ctx(low, rate: warmRate(minutesRemaining: 80))))
    }

    func testTimeLowSilentWhileCharging() {
        let rule = TimeRemainingLowRule()
        let charging = sample(pct: 20, amps: 1800, external: true, osCharging: true)
        XCTAssertNil(rule.evaluate(ctx(charging, rate: warmRate(minutesRemaining: 30))))
    }

    // MARK: Rule 3 — weak powerbank sustained + hysteresis

    func testWeakPowerbankNeedsSustainAndFiresOnce() {
        let rule = WeakPowerbankRule()
        let weak = sample(pct: 50, amps: -400, external: true, osCharging: true)
        // Not sustained yet → silent.
        XCTAssertNil(rule.evaluate(ctx(weak, rate: warmRate(minutesRemaining: 200), sustainedWeak: 30)))
        // Sustained ≥ 60s → fires once.
        XCTAssertNotNil(rule.evaluate(ctx(weak, rate: warmRate(minutesRemaining: 200), sustainedWeak: 65)))
        // Still weak → does not spam.
        XCTAssertNil(rule.evaluate(ctx(weak, rate: warmRate(minutesRemaining: 200), sustainedWeak: 120)))
        // Unplug re-arms; re-plug weak fires again.
        _ = rule.evaluate(ctx(sample(pct: 50, amps: -1800), rate: warmRate(minutesRemaining: 200)))
        XCTAssertNotNil(rule.evaluate(ctx(weak, rate: warmRate(minutesRemaining: 200), sustainedWeak: 65)))
    }

    // MARK: Rule 5 — level warnings, once per crossing, reset above 75%

    func testLevelWarningsFireOncePerCrossing() {
        let rule = LevelWarningRule()
        // Prime lastPercentage above 70.
        XCTAssertNil(rule.evaluate(ctx(sample(pct: 72, amps: -1800), rate: warmRate(minutesRemaining: 200))))
        // Cross 70 downward → fires.
        XCTAssertNotNil(rule.evaluate(ctx(sample(pct: 69, amps: -1800), rate: warmRate(minutesRemaining: 200))))
        // Hover at 69/68 → no repeat for the 70 level.
        XCTAssertNil(rule.evaluate(ctx(sample(pct: 68, amps: -1800), rate: warmRate(minutesRemaining: 200))))
        // Cross 50 → fires (different level).
        _ = rule.evaluate(ctx(sample(pct: 51, amps: -1800), rate: warmRate(minutesRemaining: 200)))
        XCTAssertNotNil(rule.evaluate(ctx(sample(pct: 49, amps: -1800), rate: warmRate(minutesRemaining: 200))))
    }

    func testLevelWarningsResetAfterRecharge() {
        let rule = LevelWarningRule()
        _ = rule.evaluate(ctx(sample(pct: 72, amps: -1800), rate: warmRate(minutesRemaining: 200)))
        XCTAssertNotNil(rule.evaluate(ctx(sample(pct: 69, amps: -1800), rate: warmRate(minutesRemaining: 200))))
        // Charge back above 75 → re-arms all levels.
        _ = rule.evaluate(ctx(sample(pct: 80, amps: 1800, external: true, osCharging: true),
                              rate: warmRate(minutesRemaining: 30)))
        // Prime above 70 again, then re-cross 70 → fires anew.
        _ = rule.evaluate(ctx(sample(pct: 72, amps: -1800), rate: warmRate(minutesRemaining: 200)))
        XCTAssertNotNil(rule.evaluate(ctx(sample(pct: 69, amps: -1800), rate: warmRate(minutesRemaining: 200))))
    }

    // MARK: Evaluator wiring — the drain-spike average + sustain plumbing

    func testEvaluatorTracksDrainSpikeSustain() {
        var eval = NotificationEvaluator()
        let base = Date(timeIntervalSince1970: 0)
        // Establish a low baseline average.
        for i in 0..<5 {
            let s = PowerSample(timestamp: base.addingTimeInterval(Double(i) * 5), hasBattery: true,
                                percentage: 60, amperageMilliAmps: -800, voltageMilliVolts: 12_600,
                                externalConnected: false, osReportsCharging: false)
            _ = eval.evaluate(eval.makeContext(sample: s, rate: warmRate(minutesRemaining: 200),
                                               timeLowMinutes: 90, timeLowRearmMinutes: 110,
                                               drainSpikeMultiplier: 1.5))
        }
        // Now spike hard and sustain > 60s; expect a drain-spike notification eventually.
        var fired = false
        for i in 5..<25 {
            let s = PowerSample(timestamp: base.addingTimeInterval(Double(i) * 5), hasBattery: true,
                                percentage: 60, amperageMilliAmps: -4000, voltageMilliVolts: 12_600,
                                externalConnected: false, osReportsCharging: false)
            let notes = eval.evaluate(eval.makeContext(sample: s, rate: warmRate(minutesRemaining: 200),
                                                       timeLowMinutes: 90, timeLowRearmMinutes: 110,
                                                       drainSpikeMultiplier: 1.5))
            if notes.contains(where: { $0.id == "drain-spike" }) { fired = true; break }
        }
        XCTAssertTrue(fired, "drain spike should fire once sustained past 60s")
    }
}
