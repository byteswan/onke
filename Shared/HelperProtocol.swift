import Foundation

/// The Mach service name the helper daemon registers and the app connects to. Must match
/// the daemon's launchd plist `MachServices` key.
let onkeHelperMachServiceName = "com.byteswan.onke.helper"

/// One process's energy contribution for a single `powermetrics` sample. Deliberately
/// small and `Codable` so it crosses the XPC boundary cheaply (spec §6.1).
///
/// `energyImpact` is a relative, unitless figure straight from `powermetrics` — it is NOT
/// watts and must never be labeled as such in the UI (spec §6.2).
struct ProcessEnergySample: Codable, Equatable, Sendable {
    var pid: Int32
    var name: String
    var energyImpact: Double
}

/// A full per-sample snapshot the daemon pushes to the app.
struct EnergySnapshot: Codable, Equatable, Sendable {
    var timestamp: Date
    var processes: [ProcessEnergySample]
}

/// XPC interface the helper *exports* (app → helper calls). Must use only Objective-C
/// bridgeable / `NSSecureCoding` types across the wire; we pass `Data` (JSON-encoded
/// snapshots) via the callback protocol below to keep the contract simple and Codable.
@objc protocol HelperProtocol {
    /// App subscribes; the helper begins running `powermetrics` and streaming snapshots.
    /// A quick version handshake also lets the app confirm it's talking to a matching
    /// helper build.
    func subscribe(withReply reply: @escaping (_ helperVersion: String) -> Void)

    /// App unsubscribes; the helper stops streaming to this client. When the last client
    /// unsubscribes (or disconnects), the helper stops `powermetrics` and — after a grace
    /// period — exits, so no root `powermetrics` runs for nobody (spec §6.1).
    func unsubscribe()

    /// Set macOS Low Power Mode via `pmset -a lowpowermode <0|1>` (spec §7.2). Root-only,
    /// so it goes through the helper. Reply carries success.
    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool) -> Void)

    /// Fallback Wi-Fi power toggle via `networksetup -setairportpower <device> <on|off>`
    /// for cases where the app's CoreWLAN call is blocked by entitlements (spec §7.2).
    func setWiFiPower(_ on: Bool, device: String, withReply reply: @escaping (Bool) -> Void)
}

/// XPC interface the *app* exports (helper → app callbacks). The helper pushes each
/// snapshot as JSON `Data` so we reuse the `Codable` models above without bridging arrays
/// of custom objects through XPC.
@objc protocol HelperClientProtocol {
    /// A new `EnergySnapshot`, JSON-encoded.
    func receiveSnapshot(_ snapshotJSON: Data)
}

/// The current helper build's version string, used for the subscribe handshake. Bumped
/// when the wire format or behaviour changes so a stale installed helper can be detected.
let onkeHelperVersion = "1"
