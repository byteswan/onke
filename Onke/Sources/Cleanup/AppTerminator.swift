import AppKit

/// Quits user apps on explicit request, with a hardcoded denylist of system-critical
/// processes that must never be offered a Quit button (spec §7.1). Never auto-kills:
/// every termination is a user click, and force-quit requires an explicit second click.
enum AppTerminator {

    /// Processes we refuse to touch — killing any of these harms the session or the OS.
    /// Matched case-insensitively against the process/app name.
    static let denylist: Set<String> = [
        "windowserver", "kernel_task", "launchd", "loginwindow", "onke",
        "finder", "dock", "systemuiserver", "coreaudiod", "mds", "mds_stores",
        "cfprefsd", "distnoted", "securityd", "opendirectoryd", "hidd",
        "com.byteswan.onke.helper",
    ]

    static func isProtected(_ name: String) -> Bool {
        denylist.contains(name.lowercased())
    }

    /// Whether an app should be offered a Quit affordance at all.
    static func canQuit(_ app: AppEnergy) -> Bool {
        !isProtected(app.name) && !isProtected(processName(pid: app.representativePid) ?? "")
    }

    /// Graceful terminate (first click). Returns false if protected or not resolvable.
    @discardableResult
    static func quit(_ app: AppEnergy) -> Bool {
        guard canQuit(app),
              let running = NSRunningApplication(processIdentifier: app.representativePid)
        else { return false }
        return running.terminate()
    }

    /// Force terminate (explicit second click only). Same guards apply.
    @discardableResult
    static func forceQuit(_ app: AppEnergy) -> Bool {
        guard canQuit(app),
              let running = NSRunningApplication(processIdentifier: app.representativePid)
        else { return false }
        return running.forceTerminate()
    }

    private static func processName(pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
