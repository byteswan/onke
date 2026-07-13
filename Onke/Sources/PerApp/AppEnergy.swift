import Foundation
import AppKit
import Darwin   // proc_pidpath

/// Per-app energy impact, aggregated from raw per-process samples (spec §6.2). The value
/// is relative and unitless — labeled "Energy impact", never watts.
struct AppEnergy: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var energyImpact: Double
    /// A representative pid for the app, used to resolve an icon / offer a Quit action.
    var representativePid: Int32
    /// Absolute executable path resolved from the pid at aggregation time (pids can die
    /// later, so we snapshot it here). Drives user-vs-system classification. nil if the
    /// process was gone or the path couldn't be read.
    var executablePath: String?

    /// Aggregate raw process samples up to the app level, most-hungry first.
    ///
    /// Grouping: processes are grouped by the running application that owns them where
    /// resolvable (via `NSRunningApplication` bundle id / localized name from the pid),
    /// falling back to the raw process name (spec §6.2 — "responsible-pid / bundle
    /// grouping where possible; fall back to process name grouping").
    static func aggregate(_ processes: [ProcessEnergySample]) -> [AppEnergy] {
        var byKey: [String: AppEnergy] = [:]

        for p in processes {
            let (key, displayName) = groupingIdentity(for: p)
            if var existing = byKey[key] {
                existing.energyImpact += p.energyImpact
                byKey[key] = existing
            } else {
                byKey[key] = AppEnergy(name: displayName,
                                       energyImpact: p.energyImpact,
                                       representativePid: p.pid,
                                       executablePath: executablePath(pid: p.pid))
            }
        }

        return byKey.values.sorted { $0.energyImpact > $1.energyImpact }
    }

    /// Absolute path of a pid's executable via `proc_pidpath` (works for daemons too,
    /// which have no NSRunningApplication). nil if the process is gone. The app runs
    /// unsandboxed, so this is permitted.
    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// Resolve a process to (groupingKey, displayName). Uses the owning app's bundle id +
    /// localized name when the pid maps to a running application; otherwise the process
    /// name is its own group.
    private static func groupingIdentity(for p: ProcessEnergySample) -> (String, String) {
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            let key = app.bundleIdentifier ?? app.localizedName ?? p.name
            let display = app.localizedName ?? p.name
            return (key, display)
        }
        return (p.name, p.name)
    }

    /// The app icon, if resolvable from the representative pid.
    var icon: NSImage? {
        NSRunningApplication(processIdentifier: representativePid)?.icon
    }
}
