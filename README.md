# Onke

A small, dark macOS battery dashboard. It shows the one number that tells the truth on
a weak USB-C powerbank: **net wattage** (signed battery amperage × voltage). macOS's own
"charging" flag lies when a brick can't keep up — Onke shows a loud amber "plugged in but
draining" state instead.

Alongside the live watts it shows battery %, time to full/empty, per-hour drain, an
in/out power breakdown, and a **Power history** screen tracking energy in vs. out per
clock hour (so you can see how much a powerbank actually gave you).

## Run it

**Requirements:** macOS 13 (Ventura) or later and Xcode.

```sh
git clone <this-repo>
cd onke
open Onke.xcodeproj
```

In Xcode: select the **Onke** scheme, set your own Team under **Signing &
Capabilities** (any free Apple ID works), then **⌘R**.

Or from the command line:

```sh
xcodebuild -project Onke.xcodeproj -scheme Onke -configuration Debug \
  -destination 'platform=macOS' build
```

The window opens on live battery data. Closing it keeps Onke running in the menu bar
(battery % lives there too); quit from there or with ⌘Q.

No battery to test against? Launch with `--demo` for a scripted timeline:

```sh
Onke.app/Contents/MacOS/Onke --demo
```

## Optional: per-app drain & power toggles

Onke can also show top apps by energy and offer power-saving toggles (Low Power Mode,
Wi-Fi, brightness). These use a small privileged helper and system controls, so they
need a signed local build and a one-time approval in System Settings — enable them from
the dashboard when you want them. Everything else works without them.

## Privacy

Client-only. **No servers, no network calls, no analytics, no telemetry — ever.** All
data stays on your machine; nothing is persisted beyond your settings and the hourly
energy history in UserDefaults.

## License

MIT — see [LICENSE](LICENSE).
