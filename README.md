# Onke

A native macOS menu-less battery/power dashboard. An always-on floating window shows your
live power state, keyed off the one number that actually tells the truth on a weak USB-C
powerbank: **net wattage** (signed battery amperage × voltage). macOS's own "charging" flag
lies when a brick can't keep up — Onke shows a loud amber "plugged in but draining" state
instead of a reassuring lie.

> **Status:** early. Phase 1 is in progress — a floating panel with live (currently
> simulated) net-watts, battery %, and effective-charging state. Real battery data,
> notifications, per-app drain attribution, and power-saving actions are on the roadmap.

## Features (planned across 3 phases)

- **Phase 1** — floating always-on panel (net watts, %, rate, time-remaining), the
  "plugged in but draining" warning, a menu bar extra, and local notifications for
  low-battery / drain-spike / weak-powerbank events.
- **Phase 2** — per-app drain attribution via a privileged helper daemon over XPC.
- **Phase 3** — one-button power cleanup: Low Power Mode, brightness floor, Wi-Fi off, and
  quitting hungry apps — each reversible.

## Build from source

Onke is open source (MIT) and has no notarization pipeline — you build it yourself with
your own signing identity.

**Requirements:** macOS 13 (Ventura) or later, Apple Silicon or Intel, Xcode.

1. Clone this repo.
2. Open `Onke.xcodeproj` in Xcode.
3. Select the `Onke` target → **Signing & Capabilities** → set your own Team.
4. Build & Run (**⌘R**). The floating panel appears mid-screen; drag it anywhere. Quit from
   the menu bar extra (the panel has no close box).

Or from the command line:

```sh
xcodebuild -project Onke.xcodeproj -scheme Onke -configuration Debug -destination 'platform=macOS' build
```

### Demo mode (no battery required)

Onke is built behind a fake power source, so every state is reachable without a real
battery (useful on a desktop Mac or for testing). Pass a launch argument:

```sh
Onke.app/Contents/MacOS/Onke --demo weakPowerbank
```

Scenarios: `discharge` (default), `weakPowerbank`, `healthyCharge`, `fullCycle`. In Xcode,
set this under **Product → Scheme → Edit Scheme → Run → Arguments**.

### Free Apple account caveat

Signing with a free (non-paid) Apple ID issues 7-day certificates. Phase-1 features are
unaffected, but the phase-2 privileged helper will re-prompt for approval after each
re-sign. A paid Apple Developer account avoids the re-prompt.

## Privacy

Client-only. **No servers, no network calls, no analytics, no telemetry — ever.** All
power data stays on your machine and nothing is persisted beyond an in-memory rolling
window and your UserDefaults settings. If you're paranoid, verify with Little Snitch: Onke
makes no outbound connections.

## License

MIT — see [LICENSE](LICENSE).
