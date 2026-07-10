import XCTest
@testable import Onke

final class AppTerminatorTests: XCTestCase {

    func testSystemCriticalProcessesAreProtected() {
        for name in ["WindowServer", "kernel_task", "launchd", "loginwindow", "Onke",
                     "Finder", "Dock"] {
            XCTAssertTrue(AppTerminator.isProtected(name),
                          "\(name) must never be quittable")
        }
    }

    func testProtectionIsCaseInsensitive() {
        XCTAssertTrue(AppTerminator.isProtected("WINDOWSERVER"))
        XCTAssertTrue(AppTerminator.isProtected("windowserver"))
    }

    func testOrdinaryAppIsNotProtected() {
        XCTAssertFalse(AppTerminator.isProtected("Safari"))
        XCTAssertFalse(AppTerminator.isProtected("Xcode"))
    }

    func testCanQuitRejectsProtectedByName() {
        let protected = AppEnergy(name: "WindowServer", energyImpact: 100, representativePid: 1)
        XCTAssertFalse(AppTerminator.canQuit(protected))
    }
}
