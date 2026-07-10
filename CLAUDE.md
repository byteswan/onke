# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

**Phase 1, in progress.** A buildable Xcode project exists with a working vertical slice: core models, the `PowerSourceProviding` protocol behind a `FakePowerSource`, a `MetricsEngine`, and a floating `NSPanel` showing live (simulated) net watts with the effective-charging color logic. Still to come in phase 1: the real IOKit provider, EMA rate/time-remaining, the 5 notification rules with hysteresis, and settings.

`docs/onke_v0_spec.md` is the authoritative source of truth for what to build — read it before making architectural decisions. This CLAUDE.md summarizes it so you can orient quickly; when the two disagree, the spec wins.

## Source Layout

Single app target `Onke`, driven by a hand-written `Onke.xcodeproj` that uses a **file-system-synchronized group** — new files added under `Onke/` are picked up automatically, so you rarely need to touch `project.pbxproj`.

- `Onke/Sources/Models/` — `PowerSample`, the raw per-sample payload everything derives from.
- `Onke/Sources/Power/` — `PowerSourceProviding` protocol + `FakePowerSource` (real IOKit impl lands here later).
- `Onke/Sources/Metrics/` — `MetricsEngine`, the `@MainActor ObservableObject` bridging provider → UI.
- `Onke/Sources/UI/` — `PanelView` (SwiftUI dashboard) and `FloatingPanel` (the `NSPanel` host).
- `Onke/Sources/App/` — `OnkeApp` (`@main`, menu bar extra) and `AppDelegate` (owns engine + panel).
- `Onke/Resources/` — `Info.plist` (`LSUIElement`), `Onke.entitlements` (App Sandbox intentionally **off** — IOKit reads + future root helper need it), `Assets.xcassets`.

## What Onke Is

A native macOS menu-less desktop app: an always-on floating window showing live battery/power state, per-app drain attribution, and local notifications for power events. Built for laptop use on USB-C powerbanks.

**Domain insight the whole app is built around:** macOS's own "charging" flag lies on weak powerbanks. The source of truth is **net wattage** = signed battery Amperage × Voltage / 10^6 (negative = discharging). Everything keys off this number, not the OS flag.

## Architecture

Two processes:

1. **Main app** (user session): metrics engine, floating panel UI, notification engine, settings, non-root cleanup actions.
2. **Privileged helper daemon** (root, phase 2+): registered via `SMAppService.daemon`, wraps `powermetrics`, streams per-process energy data to the app over **XPC**. Installed on first use of per-app features. The app must degrade gracefully (full phase-1 functionality) if the user declines the daemon.

**Central abstraction — build this first:** put the metrics layer behind a `PowerSourceProviding` protocol with two implementations — a real IOKit one and a **fake/simulated** one. The fake is not optional: it powers SwiftUI previews, demo mode, and notification testing, because real battery events can't be reproduced on demand and the dev machine may itself be a desktop with no battery.

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

## Build Order (phases are shippable checkpoints — spec §5–7, §9)

1. **Phase 1** — core metrics engine, floating non-activating `NSPanel` (SwiftUI view, `.floating` level, all-Spaces, no focus steal, position in UserDefaults), menu bar extra, notification engine (5 rules with hysteresis), settings. Build the fake provider first; slot the real IOKit provider in after.
2. **Phase 2** — privileged helper daemon + per-app drain attribution over XPC. **Do not start this until phase 1 acceptance passes.** The XPC listener must validate the connecting client's code signature; the daemon must exit when no client has connected for > 60s (no orphaned root `powermetrics`).
3. **Phase 3** — cleanup actions (quit hungry apps with a system-critical denylist, brightness/Wi-Fi/Bluetooth/Low-Power-Mode toggles, one-button Cleanup with Undo).

**Known risk areas, prototype each in isolation before wiring in** (descending risk): brightness API (DisplayServices/IOKit), `powermetrics` plist schema drift across Silicon/Intel/macOS versions, CoreWLAN entitlements, `SMAppService` approval UX.

## Build / Run / Test

Xcode-based (the spec mandates an Xcode project, not SPM-only, because it needs app + helper targets, entitlements, and launchd plists).

- **In Xcode:** open `Onke.xcodeproj`, set your own team/signing identity, then Build & Run (⌘R). Test with ⌘U.
- **Command line build:**
  ```
  xcodebuild -project Onke.xcodeproj -scheme Onke -configuration Debug -destination 'platform=macOS' build
  ```
  Add `CODE_SIGNING_ALLOWED=NO` for an unsigned local build in CI/agents.
- **Tests:** no test target exists yet. When one is added, run with `xcodebuild ... test` and filter a single test via `-only-testing:OnkeTests/<Suite>/<test>`.
- **Demo mode:** the fake provider is selected by a launch argument — `--demo <scenario>` where scenario is `discharge` (default), `weakPowerbank`, `healthyCharge`, or `fullCycle`. Set it in the scheme's Run arguments (or pass it when launching the built binary directly) to exercise states — including the amber "plugged in but draining" case — without a real battery.
