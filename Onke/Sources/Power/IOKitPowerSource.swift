import Foundation
import IOKit
import IOKit.ps

/// The real power source: reads live battery state from IOKit every `interval` seconds
/// (spec §5.1).
///
/// Two sources are combined per sample:
/// - `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` — percentage, external
///   connected flag, and macOS's (untrusted) charging flag.
/// - the `AppleSmartBattery` IORegistry entry — signed `Amperage` (mA; negative =
///   discharging) and `Voltage` (mV), which together give the hero net-watts number.
///
/// On a machine with no battery (a desktop), both sources come up empty; we emit a
/// `hasBattery == false` sample so the UI can show a friendly state instead of crashing.
final class IOKitPowerSource: PowerSourceProviding {

    private(set) var latest: PowerSample?

    private var timer: DispatchSourceTimer?
    private var onSample: ((PowerSample) -> Void)?

    func start(interval: TimeInterval, onSample: @escaping (PowerSample) -> Void) {
        stop()
        self.onSample = onSample

        emit()  // one immediate reading so the panel isn't blank until the first tick

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.emit() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onSample = nil
    }

    private func emit() {
        let sample = Self.read()
        latest = sample
        onSample?(sample)
    }

    // MARK: Reading

    /// Take one combined reading. Static + side-effect-free so it can be unit-tested.
    static func read() -> PowerSample {
        let ps = readPowerSourcesInfo()
        let battery = readSmartBattery()

        let hasBattery = ps.hasBattery || battery.amperage != nil
        return PowerSample(
            timestamp: Date(),
            hasBattery: hasBattery,
            percentage: ps.percentage ?? 0,
            amperageMilliAmps: battery.amperage ?? 0,
            voltageMilliVolts: battery.voltage ?? 0,
            externalConnected: ps.externalConnected,
            osReportsCharging: ps.osReportsCharging
        )
    }

    // MARK: IOPS (power sources)

    private struct PSInfo {
        var hasBattery = false
        var percentage: Double?
        var externalConnected = false
        var osReportsCharging = false
    }

    private static func readPowerSourcesInfo() -> PSInfo {
        var info = PSInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return info }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            // Only internal batteries carry a charge level worth showing.
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                info.hasBattery = true
                if let cur = desc[kIOPSCurrentCapacityKey] as? Double,
                   let max = desc[kIOPSMaxCapacityKey] as? Double, max > 0 {
                    info.percentage = (cur / max) * 100.0
                }
                if let charging = desc[kIOPSIsChargingKey] as? Bool {
                    info.osReportsCharging = charging
                }
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String,
               state == kIOPSACPowerValue {
                info.externalConnected = true
            }
        }
        return info
    }

    // MARK: AppleSmartBattery (signed amperage / voltage)

    private struct SmartBattery {
        var amperage: Double?   // mA, signed (negative = discharging)
        var voltage: Double?    // mV
    }

    private static func readSmartBattery() -> SmartBattery {
        var out = SmartBattery()
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return out }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else { return out }

        // "Amperage" is unsigned in the registry on some machines; the sign lives in a
        // separate flag or the value is already two's-complement. Read it as Int64 and
        // trust its sign — Apple Silicon reports it signed directly.
        if let amp = dict["Amperage"] as? Int64 {
            out.amperage = Double(amp)
        } else if let amp = dict["InstantAmperage"] as? Int64 {
            out.amperage = Double(amp)
        }
        if let volt = dict["Voltage"] as? Int64 {
            out.voltage = Double(volt)
        }
        return out
    }
}
