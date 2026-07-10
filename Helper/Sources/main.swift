import Foundation

// Root-privileged helper daemon entry point (spec §6). Registered by the app via
// `SMAppService.daemon`. It exposes an XPC Mach service, streams per-process energy from
// `powermetrics` to subscribed clients, and exits when idle. It has no UI and no user
// session — everything is driven over XPC.
let service = HelperService()
service.run()
