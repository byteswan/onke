import XCTest
@testable import Onke

final class AppEnergyTests: XCTestCase {

    func testAggregatesUnknownPidsByProcessNameAndSortsDescending() {
        // Use pids unlikely to map to a running app so grouping falls back to name.
        let raw = [
            ProcessEnergySample(pid: 999001, name: "Xcode", energyImpact: 10),
            ProcessEnergySample(pid: 999002, name: "Xcode", energyImpact: 15),
            ProcessEnergySample(pid: 999003, name: "Safari", energyImpact: 40),
        ]
        let result = AppEnergy.aggregate(raw)

        XCTAssertEqual(result.count, 2)
        // Safari (40) should sort above Xcode (25).
        XCTAssertEqual(result.first?.name, "Safari")
        XCTAssertEqual(result.first?.energyImpact, 40)
        let xcode = result.first { $0.name == "Xcode" }
        XCTAssertEqual(xcode?.energyImpact, 25, "same-name processes should sum")
    }

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertTrue(AppEnergy.aggregate([]).isEmpty)
    }
}
