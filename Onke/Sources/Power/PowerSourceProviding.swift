import Foundation

/// The seam that lets the entire UI + notification stack develop without a real battery.
///
/// Two implementations exist:
/// - a real IOKit provider (reads `IOPSCopyPowerSourcesInfo` + `AppleSmartBattery`), and
/// - ``FakePowerSource``, which scripts battery events on demand.
///
/// The fake is not optional (spec §4, §9): it powers SwiftUI previews, demo mode, and
/// notification testing, because real battery transitions can't be reproduced on command
/// and the dev machine may be a desktop with no battery at all. Build against this
/// protocol, not a concrete type.
protocol PowerSourceProviding: AnyObject {
    /// The most recent sample, if one has been read yet.
    var latest: PowerSample? { get }

    /// Begin sampling at `interval` seconds, invoking `onSample` on the main queue for
    /// each new reading. Calling `start` again replaces the previous cadence/handler.
    func start(interval: TimeInterval, onSample: @escaping (PowerSample) -> Void)

    /// Stop sampling. Safe to call when not started.
    func stop()
}
