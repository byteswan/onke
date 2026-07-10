import XCTest
@testable import Onke

final class RateEstimatorTests: XCTestCase {

    private func sample(at t: Date, pct: Double, amps: Double = -1800,
                        external: Bool = false) -> PowerSample {
        PowerSample(timestamp: t, hasBattery: true, percentage: pct,
                    amperageMilliAmps: amps, voltageMilliVolts: 12_600,
                    externalConnected: external, osReportsCharging: external)
    }

    /// Feed `count` samples 5s apart, dropping `pct` by `dropPerSample` each tick.
    private func warmedEstimator(dropPerSample: Double = 0.1, count: Int = 40)
        -> (RateEstimator.Output, RateEstimator) {
        var est = RateEstimator(expectedInterval: 5)
        var out = RateEstimator.Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: false)
        var pct = 80.0
        let base = Date(timeIntervalSince1970: 0)
        for i in 0..<count {
            let s = sample(at: base.addingTimeInterval(Double(i) * 5), pct: pct)
            out = est.ingest(s)
            pct -= dropPerSample
        }
        return (out, est)
    }

    func testNotWarmedUpBeforeTwoMinutes() {
        var est = RateEstimator(expectedInterval: 5)
        let base = Date(timeIntervalSince1970: 0)
        var out = RateEstimator.Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: false)
        // 10 samples × 5s = 45s of span — under the 120s warmup.
        for i in 0..<10 {
            out = est.ingest(sample(at: base.addingTimeInterval(Double(i) * 5), pct: 80 - Double(i) * 0.1))
        }
        XCTAssertFalse(out.isWarmedUp)
        XCTAssertNil(out.ratePercentPerHour)
        XCTAssertNil(out.timeRemaining)
    }

    func testWarmsUpAndReportsNegativeRateWhenDraining() {
        let (out, _) = warmedEstimator(dropPerSample: 0.1)
        XCTAssertTrue(out.isWarmedUp)
        let rate = try! XCTUnwrap(out.ratePercentPerHour)
        // 0.1% per 5s = 72 %/hr drain → negative.
        XCTAssertLessThan(rate, 0)
        XCTAssertEqual(rate, -72, accuracy: 5)
    }

    func testTimeToEmptyIsFiniteAndPositiveWhenDraining() {
        let (out, _) = warmedEstimator(dropPerSample: 0.1)
        let remaining = try! XCTUnwrap(out.timeRemaining)
        XCTAssertGreaterThan(remaining, 0)
    }

    func testSleepGapResetsWindow() {
        var (_, est) = warmedEstimator(dropPerSample: 0.1)
        // A sample far in the future (simulating wake after sleep) exceeds 2× interval.
        let out = est.ingest(sample(at: Date(timeIntervalSince1970: 100_000), pct: 60))
        XCTAssertFalse(out.isWarmedUp)
        XCTAssertNil(out.ratePercentPerHour)
    }

    func testNoBatteryProducesEmptyOutput() {
        var est = RateEstimator(expectedInterval: 5)
        var s = sample(at: Date(), pct: 0)
        s.hasBattery = false
        let out = est.ingest(s)
        XCTAssertFalse(out.isWarmedUp)
        XCTAssertNil(out.ratePercentPerHour)
    }
}
