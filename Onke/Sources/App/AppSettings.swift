import Foundation
import Combine

/// User-configurable settings, persisted in UserDefaults (spec §5.4 — "No files, no
/// databases"). Both the notification engine and the settings UI read from here; the
/// defaults match the spec §5.3 thresholds.
///
/// An `ObservableObject` so the settings Form binds directly; each property writes through
/// to UserDefaults on change.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register defaults so first launch reflects the spec values without a write.
        defaults.register(defaults: [
            Keys.samplingInterval: 5.0,
            Keys.panelOpacity: 1.0,
            Keys.timeLowMinutes: 90.0,
            Keys.timeLowRearmMinutes: 110.0,
            Keys.drainSpikeMultiplier: 1.5,
            Keys.notificationsEnabled: true,
        ])
    }

    private enum Keys {
        static let samplingInterval = "settings.samplingInterval"
        static let panelOpacity = "settings.panelOpacity"
        static let collapsed = "settings.collapsed"
        static let timeLowMinutes = "settings.timeLowMinutes"
        static let timeLowRearmMinutes = "settings.timeLowRearmMinutes"
        static let drainSpikeMultiplier = "settings.drainSpikeMultiplier"
        static let notificationsEnabled = "settings.notificationsEnabled"
    }

    /// Sampling cadence in seconds (spec: ≥ 5s). Changing it takes effect on next start.
    var samplingInterval: Double {
        get { defaults.double(forKey: Keys.samplingInterval) }
        set { defaults.set(max(5, newValue), forKey: Keys.samplingInterval); objectWillChange.send() }
    }

    var panelOpacity: Double {
        get { defaults.double(forKey: Keys.panelOpacity) }
        set { defaults.set(min(1, max(0.2, newValue)), forKey: Keys.panelOpacity); objectWillChange.send() }
    }

    var collapsed: Bool {
        get { defaults.bool(forKey: Keys.collapsed) }
        set { defaults.set(newValue, forKey: Keys.collapsed); objectWillChange.send() }
    }

    /// Rule #1 trigger: notify when computed time-to-empty drops below this (minutes).
    var timeLowMinutes: Double {
        get { defaults.double(forKey: Keys.timeLowMinutes) }
        set { defaults.set(newValue, forKey: Keys.timeLowMinutes); objectWillChange.send() }
    }

    /// Rule #1 re-arm: only re-arm once time-to-empty recovers above this (minutes).
    var timeLowRearmMinutes: Double {
        get { defaults.double(forKey: Keys.timeLowRearmMinutes) }
        set { defaults.set(newValue, forKey: Keys.timeLowRearmMinutes); objectWillChange.send() }
    }

    /// Rule #2 trigger: watts-out above this multiple of the rolling average.
    var drainSpikeMultiplier: Double {
        get { defaults.double(forKey: Keys.drainSpikeMultiplier) }
        set { defaults.set(newValue, forKey: Keys.drainSpikeMultiplier); objectWillChange.send() }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled); objectWillChange.send() }
    }
}
