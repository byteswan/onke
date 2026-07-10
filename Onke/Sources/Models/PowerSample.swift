import Foundation

/// One instantaneous reading of the battery/power state.
///
/// This is the raw payload a `PowerSourceProviding` emits every sample. Everything
/// downstream (rates, time-remaining, notifications, UI) is derived from these fields.
///
/// The hero metric is ``netWatts``: signed instantaneous power. macOS's own "charging"
/// flag lies on weak USB-C powerbanks — a laptop can report `isCharging == true` while
/// actually draining. Net wattage is the source of truth; see ``isEffectivelyCharging``.
struct PowerSample: Equatable {
    /// Wall-clock time the sample was taken. Used to detect sleep/wake gaps.
    var timestamp: Date

    /// Whether a battery exists at all. Desktops report `false` — the app shows a
    /// friendly "this is a desktop" state rather than crashing.
    var hasBattery: Bool

    /// Charge percentage 0...100 (CurrentCapacity / MaxCapacity).
    var percentage: Double

    /// Signed battery current in milliamps. Negative = discharging, positive = charging.
    /// Reads ~0 at full charge on AC.
    var amperageMilliAmps: Double

    /// Battery voltage in millivolts.
    var voltageMilliVolts: Double

    /// Whether an external power source (adapter/powerbank) is connected.
    var externalConnected: Bool

    /// macOS's own charging flag. Kept for display/debugging only — NOT trusted for
    /// the effective-charging decision. See ``isEffectivelyCharging``.
    var osReportsCharging: Bool

    /// Signed instantaneous power in watts. Negative = net drain, positive = net charge.
    ///
    /// `netWatts = amperage(mA) × voltage(mV) / 10^6` → (A × V) = W.
    var netWatts: Double {
        (amperageMilliAmps * voltageMilliVolts) / 1_000_000.0
    }

    /// The app's reason to exist: are we *actually* gaining charge?
    ///
    /// True only when an external source is connected AND current is flowing into the
    /// battery. A weak powerbank connected but not keeping up reads
    /// `externalConnected == true` here yet `amperageMilliAmps <= 0` — the "plugged in
    /// but draining" state the UI must show loudly (amber).
    var isEffectivelyCharging: Bool {
        externalConnected && amperageMilliAmps > 0
    }

    /// External source is connected but the battery is still losing charge — the
    /// weak-powerbank case worth surfacing prominently.
    var isPluggedButDraining: Bool {
        externalConnected && amperageMilliAmps < 0
    }
}
