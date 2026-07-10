import XCTest
@testable import Onke

@MainActor
final class EnergyLedgerTests: XCTestCase {

    private static let suite = "EnergyLedgerTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suite)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    /// Voltage fixed at 10 V so netWatts == amperage(mA) / 100 — easy mental math.
    private func sample(at date: Date, inW: Double? = nil, outW: Double? = nil,
                        milliAmps: Double = 0) -> PowerSample {
        PowerSample(timestamp: date, hasBattery: true, percentage: 50,
                    amperageMilliAmps: milliAmps, voltageMilliVolts: 10_000,
                    externalConnected: true, osReportsCharging: true,
                    systemInWatts: inW, systemLoadWatts: outW)
    }

    private var hourStart: Date {
        Calendar.current.dateInterval(of: .hour, for: Date())!.start
    }

    func testAccumulatesTelemetryIntoClockHourBucket() {
        let ledger = EnergyLedger(defaults: defaults)
        let hour = hourStart
        // First sample only primes the previous-timestamp; the second carries 10 s of energy.
        ledger.ingest(sample(at: hour, inW: 36, outW: 72), expectedInterval: 5)
        ledger.ingest(sample(at: hour.addingTimeInterval(10), inW: 36, outW: 72),
                      expectedInterval: 5)

        XCTAssertEqual(ledger.buckets.count, 1)
        XCTAssertEqual(ledger.buckets[0].hourStart, hour)
        XCTAssertEqual(ledger.buckets[0].wattHoursIn, 36.0 * 10 / 3600, accuracy: 1e-9)
        XCTAssertEqual(ledger.buckets[0].wattHoursOut, 72.0 * 10 / 3600, accuracy: 1e-9)
    }

    func testSkipsSleepWakeGaps() {
        let ledger = EnergyLedger(defaults: defaults)
        let hour = hourStart
        ledger.ingest(sample(at: hour, inW: 36, outW: 72), expectedInterval: 5)
        // 400 s gap with a 5 s cadence: the lid was closed — attribute nothing.
        ledger.ingest(sample(at: hour.addingTimeInterval(400), inW: 36, outW: 72),
                      expectedInterval: 5)

        XCTAssertTrue(ledger.buckets.isEmpty)
    }

    func testFallsBackToSignedNetSplitWithoutTelemetry() {
        let ledger = EnergyLedger(defaults: defaults)
        let hour = hourStart
        // -3600 mA at 10 V = -36 W net: all "out", nothing "in".
        ledger.ingest(sample(at: hour, milliAmps: -3600), expectedInterval: 5)
        ledger.ingest(sample(at: hour.addingTimeInterval(10), milliAmps: -3600),
                      expectedInterval: 5)

        XCTAssertEqual(ledger.buckets.count, 1)
        XCTAssertEqual(ledger.buckets[0].wattHoursIn, 0, accuracy: 1e-9)
        XCTAssertEqual(ledger.buckets[0].wattHoursOut, 36.0 * 10 / 3600, accuracy: 1e-9)
    }

    func testPersistsAndReloadsAcrossInstances() {
        let ledger = EnergyLedger(defaults: defaults)
        let hour = hourStart
        ledger.ingest(sample(at: hour, inW: 36, outW: 72), expectedInterval: 5)
        ledger.ingest(sample(at: hour.addingTimeInterval(10), inW: 36, outW: 72),
                      expectedInterval: 5)

        let reloaded = EnergyLedger(defaults: defaults)
        XCTAssertEqual(reloaded.buckets, ledger.buckets)
    }
}
