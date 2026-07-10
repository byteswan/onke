# Spec: macOS Battery Dashboard (working title: Onke)

## 1. Purpose

A native macOS menu-less desktop app that shows live battery/power state in an always-on floating window, attributes drain to apps, and fires local notifications for power-relevant events. Built for laptop use away from wall power, often on USB-C powerbanks. Key insight: macOS's "charging" flag lies on weak powerbanks — the source of truth is **net wattage** (signed battery amperage × voltage). The dashboard is built around that number.

## 2. Constraints & Non-Goals

- **Client-only.** No servers, no network calls, no analytics, no telemetry. Ever.
- **macOS 13+ (Ventura)**, Apple Silicon primary, Intel supported where APIs allow.
- **Open source (MIT).** Users build from source in Xcode with their own signing identity. No notarization pipeline needed.
- **Lightweight.** The app must not become the drain it monitors: target < 1% average CPU, sampling interval ≥ 5s, no busy polling.
- Non-goals: iOS/iPadOS, desktop Macs (app should detect no-battery and show a friendly "this is a desktop" state instead of crashing), historical charting/persistence beyond the in-memory rolling window (future, not in these 3 phases).

## 3. Tech Stack

- Swift 5.9+, SwiftUI for views, AppKit interop for the floating panel.
- Xcode project (not SPM-only) since we need app + helper targets, entitlements, and launchd plists.
- Frameworks: IOKit (power data), UserNotifications (local notifs), ServiceManagement / SMAppService (login item + privileged daemon), XPC (app ↔ helper), CoreWLAN (Wi-Fi toggle), AppKit NSRunningApplication (app termination).
- No third-party dependencies in phases 1–2. Phase 3 may optionally shell out to `blueutil` if present (see 8.3).

## 4. Architecture

Two processes:

1. **Main app** (user session): metrics engine, floating panel UI, notification engine, settings, cleanup actions that don't need root.
2. **Privileged helper daemon** (root, phase 2+): registered via `SMAppService.daemon`, wraps `powermetrics`, streams per-process energy data to the main app over XPC. Installed on first use of per-app features; app must degrade gracefully if the user declines.

Structure the metrics layer behind a protocol (e.g., `PowerSourceProviding`) with a real IOKit implementation and a fake/simulated implementation. The fake is required — it enables SwiftUI previews, demo mode, and testing of notification logic (battery events are otherwise impossible to reproduce on demand, and the developer machine may be a desktop).

## 5. Phase 1 — Core Metrics, Floating Panel, Notifications

### 5.1 Metrics engine

Sample every 5 seconds (configurable). Sources:

- `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`: percentage, charging state, power source type, external-connected flag.
- IORegistry entry `AppleSmartBattery` (IOService matching): `Amperage` (signed mA; negative = discharging), `Voltage` (mV), `CurrentCapacity`, `MaxCapacity`, `CycleCount`, `Temperature` (optional display).
- **Net watts** = Amperage × Voltage / 10^6, signed. This is the hero metric.
- **Drain/charge rate (%/hr)**: computed by the app from capacity deltas over a rolling window (exponential moving average, ~5 min span). Do NOT trust macOS's own time-remaining estimate; compute time-to-empty (or time-to-full) from the smoothed rate. Show "calculating…" until the window has enough samples (≥ 2 min).
- **Effective charging** (boolean): externalConnected AND smoothed amperage > 0. Distinct from macOS's charging flag. This distinction is the app's reason to exist.
- Handle edge cases: amperage reads 0 at full charge on AC; sleep/wake gaps must reset the rolling window (detect wall-clock jumps > 2× sample interval).

### 5.2 Floating panel

- Non-activating `NSPanel` hosting a SwiftUI view: floats above normal windows (`.floating` level), visible on all Spaces, does not steal focus, draggable anywhere, position persisted in UserDefaults.
- Layout (compact, roughly 260×180pt, top to bottom):
  1. Big signed net watts (e.g., "-8.2 W" red-tinted when discharging, "+22.4 W" green when effectively charging). Color logic based on *effective charging*, not the OS flag.
  2. Row: battery % with icon, rate in %/hr.
  3. Row: time remaining (to empty or to full, whichever applies).
  4. Status line: power source ("Battery" / "External"), effective-charging indicator with an explicit "plugged in but draining" state (the powerbank-too-weak case) — this state should be visually loud (e.g., amber).
- Small gear button → settings window. Small collapse button → shrink to just the watts number.
- Menu bar extra with the battery % as a secondary affordance and the quit/settings menu (the panel itself has no close box; closing = quitting from menu bar).

### 5.3 Notification engine

Local notifications via UserNotifications. All thresholds user-configurable in settings; defaults below. Every rule needs **hysteresis** (a buffer band so a value oscillating around a threshold doesn't spam — fire once per downward crossing, re-arm only after the value recovers past threshold + buffer or charging begins).

| # | Scenario | Default trigger | Re-arm condition |
|---|----------|----------------|------------------|
| 1 | Time remaining low | computed time-to-empty < 90 min (only when discharging, window warmed up) | time-to-empty > 110 min or effective charging |
| 2 | Drain spike | smoothed watts-out > 1.5× the 10-min rolling average, sustained ≥ 60s | drops back under 1.2× average |
| 3 | Powerbank too weak | externalConnected AND net amperage < 0, sustained ≥ 60s | effective charging or unplugged |
| 4 | Unplug the powerbank | externalConnected AND percentage ≥ 100 (or charging stopped at full) | unplugged |
| 5 | Level warnings | discharging AND % crosses 70, 50, 25, 10 (each fires once per discharge cycle) | reset all when charged back above 75% |

Notification copy should be short and specific, e.g., include the current watts or minutes in the body. Rule 2's body should say drain spiked; per-app culprit naming is added in phase 2.

### 5.4 Settings & app lifecycle

- Settings window (SwiftUI Form): sampling interval, all thresholds from 5.3, launch-at-login toggle (`SMAppService.mainApp` login item), panel opacity, collapse behavior.
- Persist in UserDefaults. No files, no databases.
- Request notification permission on first launch with a one-line explanation.

### 5.5 Phase 1 acceptance

- Panel shows live signed watts that visibly flips sign when plugging/unplugging.
- On a weak power source, panel shows the amber "plugged in but draining" state and notification #3 fires within ~90s.
- Notifications don't repeat-spam when hovering at a threshold.
- App idles < 1% CPU (verify with Activity Monitor over 10 min).
- Demo mode (fake provider) reachable via a hidden setting or launch argument, cycling through scripted scenarios to exercise all 5 notification rules.

## 6. Phase 2 — Per-App Drain Attribution (Privileged Helper)

### 6.1 Helper daemon

- Separate target, embedded in the app bundle, registered with `SMAppService.daemon(plistName:)`. First use of the per-app tab prompts the user to approve the daemon in System Settings (macOS 13 flow). The app must handle: not registered, requires approval, enabled, and registration failure — with clear UI for each.
- Daemon runs `powermetrics --samplers tasks -i 5000 -f plist` (or repeated one-shot invocations; prefer the streaming mode and parse successive plist documents from stdout). Parse per-process: pid, name, and the energy impact / CPU ms-per-s fields. Note: exact plist keys differ between Apple Silicon and Intel and across macOS versions — probe defensively, treat missing keys as 0, and log unknown structure once rather than crashing.
- XPC protocol: app subscribes; daemon pushes an array of (pid, name, energyImpact) every sample. Keep the wire format a simple Codable struct. Daemon must exit when no client has been connected for > 60s (don't run powermetrics for nobody).
- Security: the XPC listener must validate the connecting client's code signature (same team ID / bundle prefix) before serving data. Standard practice for privileged helpers; do not skip.

### 6.2 UI

- Panel gains an expandable per-app section (or a second tab): top 5–8 processes by energy impact, aggregated to the app level (group helper processes under the parent app via responsible-pid / bundle grouping where possible; fall back to process name grouping).
- Each row: app icon (if resolvable), name, relative energy bar, numeric impact. Values are relative/unitless — label the column "Energy impact", never watts (powermetrics does not give true per-app watts; do not fabricate units).
- Notification #2 (drain spike) body now names the top offender at spike time.

### 6.3 Phase 2 acceptance

- With the helper approved, per-app list populates within 15s and roughly matches Activity Monitor's Energy tab ordering.
- Declining/removing the helper leaves phase 1 features fully functional; per-app tab shows a "requires helper" explainer with a retry button.
- Killing the app kills powermetrics (no orphaned root processes — verify with `ps`).

## 7. Phase 3 — Cleanup Actions

### 7.1 Kill hungry apps

- In the per-app list, each row (excluding system-critical processes — hardcode a denylist: WindowServer, kernel_task, launchd, loginwindow, this app itself, etc.) gets a "Quit" action: `NSRunningApplication.terminate()` first, escalate to `forceTerminate()` only on explicit second click ("Force Quit?"). Never auto-kill anything; every kill is a user click.

### 7.2 System toggles ("Save power" panel section)

- **Screen brightness**: reduce to a configurable floor. Use the DisplayServices/IOKit route commonly used by open-source brightness tools; if the chosen API proves unavailable on some hardware, hide the control rather than erroring. (This is the flakiest API surface in the project — implement last, feature-flag it.)
- **Wi-Fi off**: CoreWLAN `CWInterface.setPower(false)`. May require the app to be granted Location or run into entitlement friction on newer macOS — test early in the phase; if blocked, fall back to instructing the helper daemon to run `networksetup -setairportpower <device> off`.
- **Bluetooth off**: no public API. If `blueutil` exists on PATH, offer the toggle; otherwise hide it. Do not bundle blueutil.
- **Low Power Mode on**: via the helper: `pmset -a lowpowermode 1`. Arguably the highest-value single toggle — include it.

### 7.3 One-button "Cleanup"

- A single button that: enables Low Power Mode, drops brightness to the floor, and lists (does not kill) the current top 3 energy apps with per-row Quit buttons. Explicit user confirmation for anything destructive; toggles are fine to apply immediately with an "Undo" that restores prior state (previous brightness, LPM off, Wi-Fi on).

### 7.4 Phase 3 acceptance

- Cleanup button applies toggles < 2s, Undo restores exact prior state.
- No app in the denylist ever shows a Quit button.
- All toggles individually hideable in settings.

## 8. Repo & Docs

- README: what it is, screenshot, build-from-source steps (clone → open in Xcode → set your team → run), the free-Apple-account caveat (7-day certs mean the privileged helper re-prompts after each re-sign; phase 1 features unaffected), and a privacy statement (no network, verify with Little Snitch if paranoid).
- MIT license. Conventional project layout: app target, helper target, shared Codable models in a small shared framework or target-membership shared files.

## 9. Build Order Notes for the Implementer

- Build the fake `PowerSourceProviding` first; UI and notification logic develop against it, real IOKit provider slots in after.
- Phase boundaries are shippable checkpoints — do not start the helper daemon until phase 1 acceptance passes.
- Known risk areas, in descending order: brightness API (7.2), powermetrics plist schema drift (6.1), CoreWLAN entitlements (7.2), SMAppService approval UX (6.1). Prototype each risk in isolation before wiring into the app.
