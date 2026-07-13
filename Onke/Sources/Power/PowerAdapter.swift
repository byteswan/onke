import Foundation
import IOKit.ps

/// Details about the connected power adapter, read from the **public**
/// `IOPSCopyExternalPowerAdapterDetails()` API — no private IOKit, no root, no helper.
/// Everything here is best-effort: fields are optional because cheap third-party
/// chargers and powerbanks frequently omit them (no serial, no manufacturer, etc.).
struct PowerAdapter: Equatable {
    /// Human name, e.g. "140W USB-C Power Adapter". Often absent on generic chargers.
    var name: String?
    /// Rated wattage, e.g. 140. The single most useful field.
    var watts: Int?
    /// "Apple Inc." for genuine Apple adapters; absent/blank for most third-party ones.
    var manufacturer: String?
    /// Short type description, e.g. "pd charger".
    var description: String?
    /// Negotiated voltage in millivolts.
    var voltageMilliVolts: Int?
    /// Negotiated current in milliamps.
    var currentMilliAmps: Int?
    /// Per-unit serial, when the adapter reports one — lets us recognise a specific source.
    var serial: String?
    /// Wireless (MagSafe/Qi) vs wired.
    var isWireless: Bool

    /// Reads the currently connected adapter, or nil when running on battery.
    static var current: PowerAdapter? {
        guard let raw = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
                as? [String: Any] else { return nil }

        func int(_ key: String) -> Int? { raw[key] as? Int }
        func str(_ key: String) -> String? {
            (raw[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        // The dictionary uses raw string keys (only a few have exported kIOPS… Swift
        // constants); these match what the API returns on real hardware, e.g. "Name",
        // "Manufacturer", "SerialString". "Watts"/"Current" also have constants but the
        // string keys are equivalent, so we keep one consistent style.
        return PowerAdapter(
            name: str("Name"),
            watts: int(kIOPSPowerAdapterWattsKey) ?? int("Watts"),
            manufacturer: str("Manufacturer"),
            description: str("Description"),
            voltageMilliVolts: int("AdapterVoltage"),
            currentMilliAmps: int(kIOPSPowerAdapterCurrentKey) ?? int("Current"),
            serial: str(kIOPSPowerAdapterSerialNumberKey) ?? str("SerialString"),
            isWireless: (raw["IsWireless"] as? Bool) ?? (int("IsWireless") == 1)
        )
    }

    /// Whether this is a genuine Apple adapter (manufacturer reports "Apple").
    var isApple: Bool {
        manufacturer?.localizedCaseInsensitiveContains("apple") ?? false
    }
}
