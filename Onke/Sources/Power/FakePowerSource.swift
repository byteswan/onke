import Foundation

/// A scripted `PowerSourceProviding` for previews, demo mode, and notification testing.
///
/// It walks a timeline of ``Scenario`` phases, synthesizing a plausible `PowerSample`
/// each tick: percentage drifts according to the phase's current, voltage wobbles a
/// little, and the phase's flags (external connected, etc.) pass straight through. This
/// lets us reproduce on demand the events a real battery would take hours to produce —
/// most importantly the "plugged in but draining" weak-powerbank state.
final class FakePowerSource: PowerSourceProviding {

    /// A single phase of a demo timeline.
    struct Phase {
        /// How long this phase runs before advancing to the next.
        var duration: TimeInterval
        /// Signed current in mA (negative = discharging). Drives the percentage drift.
        var amperageMilliAmps: Double
        var externalConnected: Bool
        /// What macOS *would* claim — deliberately allowed to disagree with reality so
        /// the "OS says charging but we're draining" case is exercised.
        var osReportsCharging: Bool
    }

    /// Named demo timelines. `.discharge` is the default idle behaviour; `.weakPowerbank`
    /// exercises the amber "plugged in but draining" state and notification rule #3.
    enum Scenario {
        case discharge
        case weakPowerbank
        case healthyCharge
        case fullCycle

        var phases: [Phase] {
            switch self {
            case .discharge:
                return [Phase(duration: .infinity, amperageMilliAmps: -1800,
                             externalConnected: false, osReportsCharging: false)]
            case .weakPowerbank:
                return [
                    Phase(duration: 30, amperageMilliAmps: -1800,
                          externalConnected: false, osReportsCharging: false),
                    // Plugged into a too-weak brick: OS flips its flag on, but current
                    // is still negative — net drain despite "charging".
                    Phase(duration: .infinity, amperageMilliAmps: -400,
                          externalConnected: true, osReportsCharging: true),
                ]
            case .healthyCharge:
                return [Phase(duration: .infinity, amperageMilliAmps: 2200,
                             externalConnected: true, osReportsCharging: true)]
            case .fullCycle:
                return [
                    Phase(duration: 60, amperageMilliAmps: -1800,
                          externalConnected: false, osReportsCharging: false),
                    Phase(duration: 30, amperageMilliAmps: -400,
                          externalConnected: true, osReportsCharging: true),
                    Phase(duration: 90, amperageMilliAmps: 2200,
                          externalConnected: true, osReportsCharging: true),
                ]
            }
        }
    }

    private let scenario: Scenario
    private(set) var latest: PowerSample?

    private var timer: DispatchSourceTimer?
    private var onSample: ((PowerSample) -> Void)?

    private var percentage: Double
    private var elapsedInPhase: TimeInterval = 0
    private var phaseIndex = 0
    private var interval: TimeInterval = 5

    init(scenario: Scenario = .discharge, startPercentage: Double = 82) {
        self.scenario = scenario
        self.percentage = startPercentage
    }

    func start(interval: TimeInterval, onSample: @escaping (PowerSample) -> Void) {
        stop()
        self.interval = interval
        self.onSample = onSample

        // Emit one sample immediately so the UI isn't blank until the first tick.
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
        elapsedInPhase += interval
        let phases = scenario.phases
        if phaseIndex < phases.count,
           elapsedInPhase >= phases[phaseIndex].duration,
           phaseIndex + 1 < phases.count {
            phaseIndex += 1
            elapsedInPhase = 0
        }
        emit()
    }

    private func emit() {
        let phases = scenario.phases
        let phase = phases[min(phaseIndex, phases.count - 1)]

        // Drift the charge level from the phase current: mA over the interval → mAh,
        // scaled against a nominal ~5000 mAh pack to get a %-change per tick.
        let deltaPercent = (phase.amperageMilliAmps * (interval / 3600.0)) / 5000.0 * 100.0
        percentage = min(100, max(0, percentage + deltaPercent))

        let sample = PowerSample(
            timestamp: Date(),
            hasBattery: true,
            percentage: percentage,
            amperageMilliAmps: phase.amperageMilliAmps,
            voltageMilliVolts: 12_600 + Double.random(in: -80...80),
            externalConnected: phase.externalConnected,
            osReportsCharging: phase.osReportsCharging
        )
        latest = sample
        onSample?(sample)
    }
}
