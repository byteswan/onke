import Foundation

/// Single source of truth for every user-facing string in Onke — window/menu labels,
/// dashboard copy, settings, per-app, save-power tips, analytics, and notification copy.
///
/// Static constants are plain literals; anything that embeds a value (watts, minutes,
/// percentages) is a `static func` so the format/interpolation stays correct. Edit copy
/// here rather than in the views.
enum Strings {

    // MARK: App / window / menu bar

    enum App {
        static let name = "Onke"
        static let settingsTitle = "Settings"
        static let analyticsTitle = "Power history"

        static let madeWithPrefix = "Made with"
        static let madeWithSuffix = "by Byteswan"

        // Menu bar extra
        static let noBatteryDetected = "No battery detected"
        static let openOnke = "Open Onke"
        static let powerHistory = "Power History"
        static let settingsMenuItem = "Settings…"
        static let quitOnke = "Quit Onke"

        /// Menu bar status line: "+3.2 W · 62%".
        static func menuStatus(watts: Double, percent: Int) -> String {
            String(format: "%+.1f W · %d%%", watts, percent)
        }
    }

    // MARK: Dashboard

    enum Dashboard {
        static let powerHistoryHelp = "Power history"
        static let settingsHelp = "Settings"
        static let back = "Back"
        static let backToDashboardHelp = "Back to dashboard"

        static let batteryFullCharging = "Fully Charged"
        static let pluggedButDraining = "Plugged in but draining, power source can't keep up"
        static let noBattery = "No Battery"
        static let noBatteryDetail = "Onke monitors battery power, this Mac doesn't report one."
        static let readingPowerData = "Reading power data…"

        // Status line (header dot)
        static let statusCharging = "External · Charging"
        static let statusCharged = "External · Charged"
        static let statusPluggedHolding = "External · Holding"
        static let statusPluggedDraining = "Plugged in but draining"
        static let statusOnBattery = "On Battery"

        // Stats card
        static let batteryLabel = "Battery"
        static let perHourLabel = "per hour"
        static let toFullLabel = "to full"
        static let leftLabel = "Left"

        // Section headers
        static let perAppDrainTitle = "Per App Drain"
        static let savePowerTitle = "Save Power"
        static let energyImpactTip = "The number is macOS's relative \"Energy Impact\" score for each process — the same one Activity Monitor shows. It's unitless (not watts), and only meaningful compared between apps: higher means hungrier right now."

        /// Hero subtitle: "net power out of the battery" / "net power into the battery".
        static func netPowerDirection(draining: Bool) -> String {
            "Battery \(draining ? "Draining" : "Charging")"
        }
        static func wattsIn(_ watts: Double) -> String { String(format: "%.1f W in", watts) }
        static func wattsOut(_ watts: Double) -> String { String(format: "%.1f W out", watts) }

        // MARK: Power source (adapter)

        /// One-line source label for the hero card, e.g. "140W USB-C Power Adapter · Apple"
        /// or "Power adapter" when the charger reports nothing useful.
        static func adapterLine(_ a: PowerAdapter) -> String {
            let name = a.name ?? "power adapter"
            var parts: [String] = []
            // Skip the standalone wattage when the name already spells it out
            // (e.g. "140W USB-C Power Adapter" — avoid "140W 140W …").
            if let w = a.watts, !name.localizedCaseInsensitiveContains("\(w)W") {
                parts.append("\(w)W")
            }
            parts.append(name)
            if a.isApple { parts.append("· Apple") }
            return parts.joined(separator: " ")
        }

        /// Multi-line detail for the ⓘ tooltip: every field the adapter reported.
        static func adapterDetail(_ a: PowerAdapter) -> String {
            var lines: [String] = []
            if let n = a.name { lines.append(n) }
            lines.append(a.isApple ? "Apple adapter" : (a.manufacturer ?? "Third-party or unknown maker"))
            if let w = a.watts { lines.append("Rated \(w) W") }
            if let mv = a.voltageMilliVolts, let ma = a.currentMilliAmps {
                lines.append(String(format: "%.1f V · %.2f A", Double(mv) / 1000, Double(ma) / 1000))
            }
            if let d = a.description { lines.append("Type: \(d)") }
            if a.isWireless { lines.append("Wireless charging") }
            if let s = a.serial { lines.append("Serial \(s)") }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: Settings

    enum Settings {
        static let samplingSection = "Sampling"
        static let interval = "Interval"
        static let intervalMin = "5s"
        static let intervalMax = "30s"

        static let notificationsSection = "Notifications"
        static let enableNotifications = "Enable notifications"
        static let warnUnder = "Warn me under"
        static let stopWarningAbove = "Stop warning above"
        static let drainSpikeAlert = "Drain-spike alert"

        static let perAppSection = "Per-app drain"
        static let showSystemProcesses = "Show critical processes"
        static let showSystemProcessesCaption = "Include macOS daemons and system processes in the drain list. They're locked (can't be quit); off by default so you see just the apps you can act on."

        static let generalSection = "General"
        static let launchAtLogin = "Launch at login"

        static let warnUnderTip = "Alerts you once when Onke's estimated time-to-empty drops below this, based on the actual drain it measures — not macOS's own estimate."
        static let stopWarningAboveTip = "After the low-battery alert fires, it stays quiet until estimated time-to-empty climbs back above this. Prevents repeat alerts while you hover around the threshold."
        static let drainSpikeTip = "How far above the recent 10-minute average power draw counts as a \"spike\" worth alerting on. 2.0× means \"twice the usual drain\"; lower is more sensitive, higher is quieter."

        static func intervalCaption(seconds: Int) -> String {
            "\(seconds)s between readings (applies on restart)"
        }
        static func minutes(_ value: Int) -> String { "\(value) min" }
        static func multiplier(_ value: Double) -> String { String(format: "%.1f×", value) }
    }

    // MARK: Per-app drain

    enum PerApp {
        static let measuring = "Measuring…"
        static let requiresApproval = "Per-app drain needs the Onke helper. Approve it in System Settings, then retry."
        static let failed = "Couldn't start the helper — hover for details."
        static let offByDefault = "Per-app drain uses a small privileged helper to read powermetrics. It's off by default."

        static let retry = "Retry"
        static let enable = "Enable per-app drain"
        static let openSettings = "Open Settings"

        static let systemProtectedHelp = "Critical process — Onke won't let you quit this, to protect your session."
        static let onlySystemHidden = "Only critical processes are drawing power right now. Turn on \"Show critical processes\" in Settings to see them."
        static func quitHelp(app: String) -> String { "Quit \(app)" }
    }

    // MARK: Save power

    enum SavePower {
        static let cleanupButton = "Cleanup"
        static let undo = "Undo"
        static let quit = "Quit"

        static let lowPowerMode = "Low Power Mode"
        static let wifi = "Wi-Fi"
        static let bluetooth = "Bluetooth"
        static let screenBrightness = "Screen brightness"
        static let dim = "Dim"

        enum Tips {
            static let cleanup = """
            One click does all of this:
            • Turns on Low Power Mode (via the privileged helper)
            • Drops screen brightness to 20%
            • Lists the top 3 energy-hungry apps below with Quit buttons — nothing is quit automatically

            Undo restores your previous brightness and turns Low Power Mode back off.
            """
            static let lowPower = "Toggles macOS Low Power Mode (pmset, via the privileged helper). Reduces CPU performance and background activity to stretch the battery."
            static let wifi = "Turns Wi-Fi on or off — same as the menu bar toggle. Uses CoreWLAN, falling back to networksetup via the helper if macOS blocks it."
            static let bluetooth = "Turns Bluetooth on or off (uses the blueutil tool installed on this Mac). Disconnects Bluetooth accessories while off."
            static let brightness = "On dims the built-in display to 40%; off restores it to 80%. Uses DisplayServices."
        }
    }

    // MARK: Analytics / power history

    enum Analytics {
        static let footnote = "In = energy drawn from the charger or powerbank. Out = energy the system consumed. Hours are clock hours (1300 – 1400), so totals line up with your watch."
        static let emptyTitle = "Power history"
        static let emptyBody = "No history yet — Onke records energy in/out per clock hour while it runs. Check back after an hour."

        static let hourColumn = "Hour"
        static let inOutColumn = "In / Out (Wh)"
        static let inMahColumn = "In (mAh)"
        static let mahTip = "Estimated @ 3.7V & 90% efficiencey. Equivalent to a good quality PowerBank"

        /// Watt-hours → powerbank-equivalent mAh: cells are rated at 3.7 V, plus a 10%
        /// bump for real-world conversion loss (a powerbank gives up more than the ideal).
        static func mAh(fromWattHours wh: Double) -> Double {
            (wh * 1000 / 3.7) * 1.1
        }
    }

    // MARK: Notifications

    enum Notifications {
        static let timeLowTitle = "Battery running low"
        static func timeLowBody(minutes: Int) -> String {
            "About \(minutes) min left at the current drain."
        }

        static let drainSpikeTitle = "Power draw spiked"
        static func drainSpikeBody(watts: Double, topOffender: String?) -> String {
            let who = topOffender.map { " — \($0) is the top draw." } ?? ""
            return String(format: "Now pulling %.1f W.%@", watts, who)
        }

        static let weakPowerbankTitle = "Power source too weak"
        static func weakPowerbankBody(watts: Double) -> String {
            String(format: "Plugged in but still draining (%.1f W). Try a stronger adapter.", watts)
        }

        static let unplugFullTitle = "Battery full"
        static let unplugFullBody = "Fully charged — you can unplug the power source."

        static func levelTitle(percent: Int) -> String { "Battery at \(percent)%" }
        static func levelBody(threshold: Double) -> String {
            switch threshold {
            case 10: return "Critically low — connect power soon."
            case 25: return "Getting low."
            default: return "Heads up on your battery level."
            }
        }
    }
}
