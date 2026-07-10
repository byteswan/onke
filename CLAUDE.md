# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

**Greenfield.** There is no source code yet — only `docs/onke_v0_spec.md`, which is the authoritative source of truth for what to build. Read it before making architectural decisions. This CLAUDE.md summarizes that spec so you can orient quickly; when the two disagree, the spec wins.

Note: the current `.gitignore` is a stale Flutter template inherited at repo creation. It is wrong for this project and should be replaced with a Swift/Xcode `.gitignore` when the Xcode project lands.

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

- Open the project in Xcode, set your own team/signing identity, then Build & Run (⌘R). Test with ⌘U.
- There is **no `.xcodeproj` yet**, so concrete `xcodebuild` scheme/target names are not yet known. Once the Xcode project exists, add the real `xcodebuild -scheme … build`/`test` invocations and single-test filters here.
- Demo mode (fake provider) should be reachable via a hidden setting or launch argument to exercise all notification rules without real battery events.
