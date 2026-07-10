import Foundation

/// A scripted power source for demo mode (spec §5.5): reachable via the hidden `--demo`
/// launch argument so all UI states and every notification rule can be exercised without a
/// real battery (e.g. on a desktop Mac, or to show the app off).
///
/// This is a shipped, first-class feature — distinct from the test-only `FakePowerSource`.
/// It is *only* instantiated when `--demo` is passed; the normal launch path uses
/// `IOKitPowerSource`. The scenario compresses events that would take hours on real
/// hardware into ~minutes so a viewer can watch each notification fire.
final class DemoPowerSource: PowerSourceProviding {

    private(set) var latest: PowerSample?
    private var timer: DispatchSourceTimer?
    private var onSample: ((PowerSample) -> Void)?
    private var interval: TimeInterval = 5
    private var percentage: Double = 95
    private var elapsed: TimeInterval = 0

    func start(interval: TimeInterval, onSample: @escaping (PowerSample) -> Void) {
        stop()
        self.interval = interval
        self.onSample = onSample
        emit()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onSample = nil
    }

    private func tick() {
        elapsed += interval
        emit()
    }

    /// A single phase's electrical state.
    private struct Phase { var amps: Double; var external: Bool; var osCharging: Bool }

    /// Timeline that walks through: fast discharge (level warnings + time-low), a weak
    /// powerbank (amber + rule #3), then a healthy charge to full (unplug-at-full).
    /// Percentages are exaggerated by the drift math so crossings happen quickly.
    private func phase(at t: TimeInterval) -> Phase {
        switch t {
        case ..<120:  return Phase(amps: -4500, external: false, osCharging: false) // steep drain
        case ..<180:  return Phase(amps: -600,  external: true,  osCharging: true)  // weak brick
        default:      return Phase(amps: 3500,  external: true,  osCharging: true)  // real charge
        }
    }

    private func emit() {
        let p = phase(at: elapsed)
        // Exaggerated drift so level thresholds are crossed within the demo's minutes.
        let deltaPercent = (p.amps * (interval / 3600.0)) / 2000.0 * 100.0
        percentage = min(100, max(0, percentage + deltaPercent))

        let sample = PowerSample(
            timestamp: Date(),
            hasBattery: true,
            percentage: percentage,
            amperageMilliAmps: p.amps,
            voltageMilliVolts: 12_600,
            externalConnected: p.external,
            osReportsCharging: p.osCharging)
        latest = sample
        onSample?(sample)
    }
}
