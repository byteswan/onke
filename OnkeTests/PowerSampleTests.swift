import XCTest
@testable import Onke

/// Covers the core derivations everything downstream keys off, plus the fake provider
/// (which now lives here in the test target, not the shipped app).
final class PowerSampleTests: XCTestCase {

    private func sample(amps: Double, volts: Double = 12_600, external: Bool) -> PowerSample {
        PowerSample(timestamp: Date(), hasBattery: true, percentage: 50,
                    amperageMilliAmps: amps, voltageMilliVolts: volts,
                    externalConnected: external, osReportsCharging: external)
    }

    func testNetWattsSignedFromAmperageAndVoltage() {
        // -1800 mA × 12600 mV / 1e6 = -22.68 W
        let s = sample(amps: -1800, external: false)
        XCTAssertEqual(s.netWatts, -22.68, accuracy: 0.001)
    }

    func testEffectiveChargingRequiresExternalAndPositiveCurrent() {
        XCTAssertTrue(sample(amps: 2200, external: true).isEffectivelyCharging)
        // Plugged in but current still negative — the weak-powerbank case.
        XCTAssertFalse(sample(amps: -400, external: true).isEffectivelyCharging)
        // Positive current but nothing plugged in shouldn't happen; guard anyway.
        XCTAssertFalse(sample(amps: 2200, external: false).isEffectivelyCharging)
    }

    func testPluggedButDrainingIsTheAmberState() {
        XCTAssertTrue(sample(amps: -400, external: true).isPluggedButDraining)
        XCTAssertFalse(sample(amps: -400, external: false).isPluggedButDraining)
        XCTAssertFalse(sample(amps: 2200, external: true).isPluggedButDraining)
    }

    func testFakeProviderEmitsImmediatelyOnStart() {
        let fake = FakePowerSource(scenario: .weakPowerbank)
        let received = expectation(description: "first sample")
        fake.start(interval: 5) { _ in received.fulfill() }
        wait(for: [received], timeout: 1)
        fake.stop()
        XCTAssertNotNil(fake.latest)
    }
}
