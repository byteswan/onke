import AppKit

/// Plain-English descriptions for common processes, plus the critical / not-critical
/// classification that drives the lock and the "show critical processes" filter.
///
/// Classification is a single boolean (`isCritical`): the base rule is "an `.app` bundle
/// is not critical, everything else is", with explicit override lists that take priority.
/// macOS has no per-process description API, so descriptions come from a small curated
/// table, falling back to the bundle identifier.
enum ProcessCatalog {

    /// Curated blurbs keyed by lowercased process / app name. Deliberately terse — 4–5
    /// words, just enough to know what it is. For protected processes we don't spell out
    /// consequences of quitting, since the UI already blocks that. Extend as needed.
    private static let blurbs: [String: String] = [
        // System-critical (also in AppTerminator.denylist — the UI blocks quitting these)
        "windowserver": "Draws the screen",
        "kernel_task": "The macOS kernel",
        "launchd": "Launches every other process",
        "loginwindow": "Your login session",
        "finder": "Desktop and file windows",
        "dock": "The Dock and Mission Control",
        "systemuiserver": "Menu bar status items",
        "coreaudiod": "System audio",
        "mds": "Spotlight indexing",
        "mds_stores": "Spotlight index storage",
        "cfprefsd": "App preferences storage",
        "securityd": "Keychain and security",
        "opendirectoryd": "User accounts and login",
        "hidd": "Keyboard, trackpad, and mouse input",
        "distnoted": "System-wide notifications",

        // Common Apple background daemons people see near the top of the list. These
        // aren't in NSRunningApplication, so a static description is the only option.
        "duetexpertd": "Predicts app and Siri suggestions",
        "peopled": "Contacts and People suggestions",
        "photoanalysisd": "Analyses your photo library",
        "photolibraryd": "Photos library management",
        "mediaanalysisd": "Scans photos and videos",
        "cloudd": "iCloud syncing",
        "bird": "iCloud Drive and documents",
        "nsurlsessiond": "Background downloads and uploads",
        "apsd": "Apple push notifications",
        "assistantd": "Siri background service",
        "siriknowledged": "Siri knowledge and suggestions",
        "spotlightknowledged": "Spotlight suggestions",
        "knowledge-agent": "On-device activity learning",
        "contextstored": "System context and usage data",
        "corespeechd": "Speech and dictation",
        "commcenter": "Cellular and phone services",
        "rapportd": "Continuity and Handoff",
        "sharingd": "AirDrop and Handoff",
        "bluetoothd": "Bluetooth service",
        "wifianalyticsd": "Wi-Fi diagnostics",
        "locationd": "Location Services",
        "timed": "System clock and time sync",
        "backupd": "Time Machine backups",
        "mdworker": "Spotlight indexing worker",
        "mdbulkimport": "Spotlight bulk import",
        "syncdefaultsd": "iCloud settings sync",
        "accountsd": "Internet accounts",
        "callservicesd": "FaceTime and calls",
        "identityservicesd": "iMessage and FaceTime identity",
        "imagent": "iMessage service",
        "trustd": "Certificate validation",
        "notifyd": "Notification delivery",
        "powerd": "Power management",
        "thermalmonitord": "Thermal monitoring",
        "watchdogd": "System health monitoring",
        "logd": "System logging",
        "coreauthd": "Touch ID and authentication",
        "tccd": "Privacy permission prompts",
        "runningboardd": "App lifecycle management",
        "dasd": "Background task scheduling",
        "gamepolicyd": "Game Mode policy",
        "spindump": "Diagnostics sampler",

        // Common user apps
        "safari": "Apple's web browser",
        "google chrome": "Google's web browser",
        "chrome": "Google's web browser",
        "firefox": "Mozilla's web browser",
        "com.apple.webkit.webcontent": "A web page in Safari",
        "spotlight": "Spotlight search",
        "zoom": "Zoom video calls",
        "slack": "Slack messaging",
        "notes": "Apple Notes",
        "music": "Apple Music",
        "terminal": "The Terminal",
        "xcode": "Apple's developer IDE",
    ]

    /// A description for a row: the curated blurb if we have one, otherwise the bundle
    /// identifier resolved from the pid, otherwise nil.
    static func describe(_ app: AppEnergy) -> String? {
        if let blurb = blurbs[app.name.lowercased()] { return blurb }
        if let bundleID = NSRunningApplication(processIdentifier: app.representativePid)?.bundleIdentifier {
            return bundleID
        }
        return nil
    }

    // MARK: - Critical / not-critical classification

    /// Names (lowercased, matched against the process/app name) that are ALWAYS critical,
    /// overriding the base rule. Use for anything that must stay locked regardless of how
    /// it's packaged.
    private static let alwaysCritical: Set<String> = AppTerminator.denylist

    /// Names (lowercased) that are ALWAYS non-critical, overriding the base rule. Use to
    /// un-lock specific safe processes (e.g. a well-known daemon you're fine quitting).
    private static let neverCritical: Set<String> = [
        // Onke itself and the Finder/Dock are user-facing — quit them the normal way, but
        // don't lock them here just because they happen to be on the terminator denylist.
        "onke", "finder", "dock",
    ]

    /// Whether this row is a visible **application** (has an `.app` bundle). Terminal,
    /// Safari, Onke, Finder all live inside an `.app`; `duetexpertd`, `cloudd`, `mds` do
    /// not — regardless of whether Apple ships them under /System.
    private static func isAppBundle(_ app: AppEnergy) -> Bool {
        if let path = app.executablePath {
            return path.contains(".app/Contents/")
        }
        // No path: if the pid maps to a running GUI application, it's an app.
        return NSRunningApplication(processIdentifier: app.representativePid) != nil
    }

    /// The one classification: critical vs not. Override lists win; otherwise the base
    /// rule is "an `.app` is not critical, everything else (daemons and system processes)
    /// is critical". Critical processes are locked (no Quit button) and hidden unless the
    /// user opts to show them.
    static func isCritical(_ app: AppEnergy) -> Bool {
        let name = app.name.lowercased()
        if neverCritical.contains(name) { return false }
        if alwaysCritical.contains(name) { return true }
        return !isAppBundle(app)
    }
}
