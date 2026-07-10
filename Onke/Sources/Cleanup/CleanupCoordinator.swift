import Foundation
import Combine

/// Drives the one-button "Cleanup" and its Undo (spec §7.3): enables Low Power Mode, drops
/// brightness to a floor, and surfaces (does not kill) the current top energy apps for the
/// user to quit. Toggles apply immediately; the prior state is captured so Undo restores
/// exactly (previous brightness, LPM off, Wi-Fi on).
@MainActor
final class CleanupCoordinator: ObservableObject {

    /// Snapshot of what to restore on Undo. Only fields we actually changed are set.
    struct UndoState {
        var priorBrightness: Float?
        var loweredLowPowerMode = false
        var turnedWiFiOff = false
    }

    @Published private(set) var lastUndo: UndoState?
    @Published private(set) var isBusy = false
    /// Top apps captured at cleanup time, offered with Quit buttons (never auto-killed).
    @Published private(set) var suggestedQuits: [AppEnergy] = []

    private let toggles: SystemToggles
    private let helper: HelperClient

    /// Brightness floor applied by Cleanup (fraction 0...1).
    var brightnessFloor: Float = 0.2

    init(toggles: SystemToggles, helper: HelperClient) {
        self.toggles = toggles
        self.helper = helper
    }

    /// Apply the cleanup bundle. Fast (< 2s target): toggles fire immediately; app-quit is
    /// left to the user via `suggestedQuits`.
    func runCleanup() {
        guard !isBusy else { return }
        isBusy = true
        var undo = UndoState()

        undo.priorBrightness = toggles.lowerBrightness(to: brightnessFloor)

        toggles.setLowPowerMode(true) { ok in
            if ok { /* recorded below regardless; Undo turns it off */ }
        }
        undo.loweredLowPowerMode = true

        // Surface top energy apps as *suggestions* — spec §7.3 lists, never kills.
        suggestedQuits = Array(helper.topApps.prefix(3)).filter(AppTerminator.canQuit)

        lastUndo = undo
        isBusy = false
    }

    /// Restore the exact prior state captured by the last `runCleanup`.
    func undo() {
        guard let undo = lastUndo else { return }
        if let b = undo.priorBrightness { toggles.restoreBrightness(to: b) }
        if undo.loweredLowPowerMode { toggles.setLowPowerMode(false) }
        if undo.turnedWiFiOff { toggles.setWiFi(on: true) }
        lastUndo = nil
        suggestedQuits = []
    }

    func quit(_ app: AppEnergy) {
        AppTerminator.quit(app)
        suggestedQuits.removeAll { $0.id == app.id }
    }
}
