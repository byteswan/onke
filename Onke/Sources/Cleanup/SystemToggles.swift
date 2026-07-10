import Foundation
import CoreWLAN
import ServiceManagement

/// The "Save power" system toggles (spec §7.2). Each is best-effort and independently
/// available: if the underlying API is missing or blocked, the corresponding control is
/// hidden rather than erroring. State needed for Undo (spec §7.3) is captured on apply.
@MainActor
final class SystemToggles {

    private let helper: HelperClient

    init(helper: HelperClient) {
        self.helper = helper
    }

    // MARK: Brightness (DisplayServices — flakiest API, feature-flagged)

    /// Whether brightness control is available on this hardware. Probed once; if the
    /// private DisplayServices entry point can't be resolved the whole control is hidden.
    private(set) lazy var brightnessAvailable: Bool = DisplayBrightness.isAvailable

    /// Current main-display brightness 0...1, or nil if unavailable.
    var currentBrightness: Float? { DisplayBrightness.get() }

    /// Drop brightness to a floor (0...1). Returns the prior value for Undo, or nil.
    @discardableResult
    func lowerBrightness(to floor: Float) -> Float? {
        guard brightnessAvailable, let prior = DisplayBrightness.get() else { return nil }
        DisplayBrightness.set(floor)
        return prior
    }

    func restoreBrightness(to value: Float) {
        guard brightnessAvailable else { return }
        DisplayBrightness.set(value)
    }

    // MARK: Wi-Fi (CoreWLAN, with helper fallback)

    var wifiAvailable: Bool { CWWiFiClient.shared().interface() != nil }

    var wifiIsOn: Bool { CWWiFiClient.shared().interface()?.powerOn() ?? false }

    /// Turn Wi-Fi off/on. Tries CoreWLAN first; if that throws (entitlement friction on
    /// newer macOS, spec §7.2) falls back to the helper's `networksetup` route.
    func setWiFi(on: Bool) {
        guard let iface = CWWiFiClient.shared().interface() else { return }
        do {
            try iface.setPower(on)
        } catch {
            let device = iface.interfaceName ?? "en0"
            (helper.helperProxy())?.setWiFiPower(on, device: device) { _ in }
        }
    }

    // MARK: Bluetooth (blueutil if present, else hidden)

    /// Bluetooth has no public toggle API; we only offer it when `blueutil` is on PATH
    /// (spec §7.2 — do not bundle blueutil).
    private(set) lazy var bluetoothAvailable: Bool = BlueUtil.isPresent

    func setBluetooth(on: Bool) {
        BlueUtil.setPower(on)
    }

    // MARK: Low Power Mode (via helper / pmset)

    func setLowPowerMode(_ on: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let proxy = helper.helperProxy() else { completion(false); return }
        proxy.setLowPowerMode(on) { ok in
            Task { @MainActor in completion(ok) }
        }
    }
}

// MARK: - blueutil shell-out

private enum BlueUtil {
    static let path: String? = {
        for candidate in ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }()

    static var isPresent: Bool { path != nil }

    static func setPower(_ on: Bool) {
        guard let path else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--power", on ? "1" : "0"]
        try? proc.run()
    }
}
