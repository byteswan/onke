# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

**All three phases implemented; compile-clean with 25 passing unit tests.** What that means precisely, because it matters:

- **Verified working:** build (app + helper + tests), the pure-logic unit tests (net-watts, `RateEstimator`, notification rules/hysteresis, app aggregation, terminator denylist, hourly `EnergyLedger`), the **real IOKit read on live hardware** (probed directly, including `PowerTelemetryData` in/out watts), and the app launching on real battery data.
- **NOT yet runtime-verified** (needs a signed build and/or mutates the system, so left for manual testing): the privileged helper daemon registering + streaming `powermetrics`, XPC signature validation, per-app data populating, notification banners actually posting, and every Phase 3 toggle (brightness/Wi-Fi/Bluetooth/`pmset`/app-quit/Cleanup-Undo). `SMAppService` registration and XPC signature checks require the user's own signing identity.

`docs/onke_v0_spec.md` is the authoritative source of truth for what to build — read it before making architectural decisions. This CLAUDE.md summarizes it so you can orient quickly; when the two disagree, the spec wins.

## Source Layout

Three targets in a hand-written `Onke.xcodeproj`: **`Onke`** (app), **`OnkeHelper`** (root daemon, embedded in the app bundle via a Copy Files phase), **`OnkeTests`**. Each target uses a **file-system-synchronized group**, so new files under a target's folder are picked up automatically — you rarely touch `project.pbxproj`. `Shared/` is a synchronized group referenced by *both* app and helper.

App (`Onke/Sources/`):
- `Models/` — `PowerSample`: the raw per-sample payload; owns `netWatts`, `isEffectivelyCharging`, `isPluggedButDraining`.
- `Power/` — `PowerSourceProviding` protocol, real `IOKitPowerSource`, and `DemoPowerSource` (the shipped `--demo` source). The scripted `FakePowerSource` lives in **OnkeTests**, not the app.
- `Metrics/` — `MetricsEngine` (`@MainActor ObservableObject`, publishes sample + rate, emits `didSample`), `RateEstimator` (pure EMA rate/time-remaining), and `EnergyLedger` (hourly in/out watt-hours in clock-hour buckets, persisted as JSON in UserDefaults, sleep-gap aware).
- `Notifications/` — `NotificationRules` (5 rules, each a hysteresis state machine) and `NotificationEngine` (`NotificationEvaluator` pure core + a `UNUserNotificationCenter` shell).
- `PerApp/` — `HelperClient` (SMAppService state + XPC), `AppEnergy` (per-app aggregation), `PerAppView`.
- `Cleanup/` — `AppTerminator` (denylist + terminate/forceTerminate), `SystemToggles`, `DisplayBrightness` (private DisplayServices via `dlopen`), `CleanupCoordinator` (Cleanup + Undo), `SavePowerView`.
- `UI/` — `Theme` (dark theme, **single source of every color**: #121212 background, mint accent, `Theme.action` for anything pressable; `.card()` modifier, `SectionHeader`, `InfoTip` popover), `ContentView` (main-window dashboard; `UIState.screen` flips between dashboard/settings/analytics in-window), `SettingsView` (embedded pane, never a separate window), `AnalyticsView` ("Power history" hourly in/out table).
- `App/` — `OnkeApp` (`@main`, `Window` scene + menu bar extra), `AppDelegate` (owns everything; no window code beyond dock-reopen), `AppSettings` (UserDefaults store).
- `Resources/` — `Info.plist`, `Onke.entitlements` (App Sandbox **off** — IOKit + root helper), `Assets.xcassets`.

Helper (`Helper/`): `Sources/main.swift`, `HelperService` (XPC listener + client bookkeeping + idle exit + pmset/networksetup), `PowerMetricsRunner` (streaming plist parser); plus `com.byteswan.onke.helper.plist` (launchd) and `Helper.entitlements`.

Shared (`Shared/`): `HelperProtocol` (XPC contract + Codable wire models), `CodeSignatureValidator` (`SecCode` peer validation).

## What Onke Is

A native macOS desktop app: a normal window (dock icon, macOS-restored position) showing live battery/power state, per-app drain attribution, and local notifications for power events, plus a menu bar extra so monitoring continues with the window closed. Dark-only UI themed after the yak mac app (see `UI/Theme.swift`). Built for laptop use on USB-C powerbanks.

**Domain insight the whole app is built around:** macOS's own "charging" flag lies on weak powerbanks. The source of truth is **net wattage** = signed battery Amperage × Voltage / 10^6 (negative = discharging). Everything keys off this number, not the OS flag.

## Architecture

Two processes:

1. **Main app** (user session): metrics engine, main-window dashboard UI, notification engine, settings, non-root cleanup actions.
2. **Privileged helper daemon** (root, phase 2+): registered via `SMAppService.daemon`, wraps `powermetrics`, streams per-process energy data to the app over **XPC**. Installed on first use of per-app features. The app must degrade gracefully (full phase-1 functionality) if the user declines the daemon.

**Central abstraction:** the metrics layer sits behind a `PowerSourceProviding` protocol. Three implementations, deliberately separated by where they run:
- `IOKitPowerSource` — the real one (app, default).
- `DemoPowerSource` — a shipped scripted source reachable only via the hidden `--demo` launch arg (spec §5.5), so demo/showcase state ships but isn't the default.
- `FakePowerSource` — the fuller scripted source for **tests only**; it lives in `OnkeTests`, so no mock code ships in the app. SwiftUI previews use a tiny inline `PreviewPowerSource` under `#if DEBUG`.

### Key derived concepts

- **Net watts** (hero metric): signed Amperage × Voltage / 10^6.
- **Effective charging** = `externalConnected AND smoothed amperage > 0`. Distinct from macOS's charging flag — this distinction is the app's reason to exist. The "plugged in but draining" (weak-powerbank) state must be visually loud (amber).
- **Rates & time-remaining** are computed by the app from capacity deltas over a rolling EMA window (~5 min). Do NOT trust macOS's own time-remaining estimate. Reset the rolling window on sleep/wake gaps (detect wall-clock jumps > 2× sample interval).
- **Notification rules all require hysteresis**: fire once per crossing, re-arm only after the value recovers past threshold + buffer (or charging begins). This is central to avoiding notification spam and applies to every rule in spec §5.3.

## Constraints That Shape Every Decision (spec §2)

- **Client-only.** No servers, network calls, analytics, or telemetry — ever.
- **Lightweight.** Must not become the drain it monitors: target < 1% average CPU, sampling interval ≥ 5s, no busy polling.
- **Persistence is UserDefaults only.** No files, no databases (beyond the in-memory rolling window).
- **macOS 13+ (Ventura)**, Apple Silicon primary, Intel where APIs allow. Detect no-battery/desktop and show a friendly state instead of crashing.
- **MIT open source.** Users build from source with their own signing identity — no notarization pipeline. Free-Apple-account signing means 7-day certs, so the privileged helper re-prompts after each re-sign (phase 1 unaffected).

## Build Order (all three phases now implemented — spec §5–7, §9)

1. **Phase 1** ✅ — metrics engine (real IOKit), `RateEstimator` EMA rate/time-remaining, main dashboard window (SwiftUI `Window` scene; macOS restores its frame), menu bar extra, notification engine (5 rules with hysteresis), in-window settings + launch-at-login, demo mode. *(Deviation from spec §5.2: the original floating `NSPanel` was replaced by a normal window at the user's request.)*
2. **Phase 2** ✅ — `OnkeHelper` daemon (embedded, `SMAppService.daemon`), per-app drain over XPC. The XPC listener validates the connecting client's code signature (`CodeSignatureValidator`); the daemon exits after 60s with no clients (no orphaned root `powermetrics`).
3. **Phase 3** ✅ — cleanup actions (quit hungry apps with a system-critical denylist, brightness/Wi-Fi/Bluetooth/Low-Power-Mode toggles, one-button Cleanup with Undo).

**Known risk areas (descending risk), each isolated as flagged**: brightness API (`DisplayBrightness` resolves DisplayServices via `dlopen`, hides the control if unavailable), `powermetrics` plist schema drift (`PowerMetricsRunner` probes multiple key spellings, treats missing as 0, logs unknown structure once), CoreWLAN entitlements (`SystemToggles` falls back to the helper's `networksetup`), `SMAppService` approval UX (`HelperClient` models notRegistered/requiresApproval/enabled/failed).

## Build / Run / Test

Xcode-based (the spec mandates an Xcode project, not SPM-only, because it needs app + helper targets, entitlements, and launchd plists).

- **In Xcode:** open `Onke.xcodeproj`, set your own team/signing identity, then Build & Run (⌘R). Test with ⌘U.
- **Command line build:**
  ```
  xcodebuild -project Onke.xcodeproj -scheme Onke -configuration Debug -destination 'platform=macOS' build
  ```
  Add `CODE_SIGNING_ALLOWED=NO` for an unsigned local build in CI/agents.
- **Tests:** `xcodebuild -project Onke.xcodeproj -scheme Onke -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`. Filter a single test via `-only-testing:OnkeTests/<Suite>/<testMethod>` (e.g. `-only-testing:OnkeTests/NotificationRulesTests/testTimeLowFiresOnceThenHoldsUntilRecovery`). Tests are pure-logic and need no battery or helper.
- **Build just the helper:** `xcodebuild -project Onke.xcodeproj -target OnkeHelper build`.
- **Demo mode:** `--demo` selects `DemoPowerSource` (a scripted timeline: steep discharge → weak powerbank → healthy charge, exercising all 5 notification rules). Set it in the scheme's Run arguments or pass it to the built binary directly. Without `--demo`, the app reads the real battery.

## Testing the privileged surface (manual)

The helper daemon and Phase 3 system toggles can't be verified unattended — they need the user's signing identity and/or mutate the machine. To test: build & run signed from Xcode, expand **Per-app drain** → **Enable**, approve the daemon in System Settings ▸ General ▸ Login Items, then confirm per-app rows populate. Verify no orphaned root process with `ps aux | grep powermetrics` after quitting. Toggles (LPM/Wi-Fi/brightness/quit) each mutate real state — test individually and use **Undo**.
