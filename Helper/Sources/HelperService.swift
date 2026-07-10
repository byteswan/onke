import Foundation

/// The root-side XPC service. Accepts connections from validly-signed Onke clients, runs
/// `powermetrics` only while at least one client is subscribed, fans each snapshot out to
/// all subscribers, and exits when idle so no root `powermetrics` lingers (spec §6.1).
final class HelperService: NSObject, NSXPCListenerDelegate, HelperProtocol {

    private let listener: NSXPCListener
    private let runner: PowerMetricsRunner
    private let encoder = JSONEncoder()

    /// Live subscriber connections, keyed by ObjectIdentifier of the connection.
    private var subscribers: [ObjectIdentifier: NSXPCConnection] = [:]

    /// After the last unsubscribe/disconnect we wait this long before exiting, so brief
    /// reconnections don't thrash the daemon.
    private let idleGrace: TimeInterval = 60
    private var idleTimer: DispatchSourceTimer?

    override init() {
        listener = NSXPCListener(machServiceName: onkeHelperMachServiceName)
        runner = PowerMetricsRunner()
        super.init()
        listener.delegate = self
        runner.onSnapshot = { [weak self] snapshot in
            self?.broadcast(snapshot)
        }
    }

    func run() {
        listener.resume()
        armIdleExit()          // exit if nobody ever connects
        dispatchMain()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Reject any peer that isn't a validly-signed Onke build (spec §6.1).
        guard CodeSignatureValidator.isValidPeer(pid: connection.processIdentifier) else {
            NSLog("Onke helper: rejected unsigned/untrusted XPC peer")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: HelperClientProtocol.self)

        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.removeSubscriber(connection)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.removeSubscriber(connection)
        }

        connection.resume()
        return true
    }

    // MARK: HelperProtocol

    func subscribe(withReply reply: @escaping (String) -> Void) {
        if let connection = NSXPCConnection.current() {
            subscribers[ObjectIdentifier(connection)] = connection
            cancelIdleExit()
            if !runner.isRunning { runner.start() }
        }
        reply(onkeHelperVersion)
    }

    func unsubscribe() {
        if let connection = NSXPCConnection.current() {
            removeSubscriber(connection)
        }
    }

    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool) -> Void) {
        reply(runTool("/usr/bin/pmset", ["-a", "lowpowermode", enabled ? "1" : "0"]))
    }

    func setWiFiPower(_ on: Bool, device: String, withReply reply: @escaping (Bool) -> Void) {
        reply(runTool("/usr/sbin/networksetup",
                      ["-setairportpower", device, on ? "on" : "off"]))
    }

    /// Run a system tool as root and report whether it exited 0.
    private func runTool(_ path: String, _ args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            NSLog("Onke helper: \(path) failed: \(error)")
            return false
        }
    }

    // MARK: Subscriber bookkeeping

    private func removeSubscriber(_ connection: NSXPCConnection) {
        subscribers.removeValue(forKey: ObjectIdentifier(connection))
        if subscribers.isEmpty {
            runner.stop()
            armIdleExit()
        }
    }

    private func broadcast(_ snapshot: EnergySnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        for connection in subscribers.values {
            let proxy = connection.remoteObjectProxy as? HelperClientProtocol
            proxy?.receiveSnapshot(data)
        }
    }

    // MARK: Idle exit

    private func armIdleExit() {
        cancelIdleExit()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + idleGrace)
        timer.setEventHandler {
            NSLog("Onke helper: idle for \(Int(60))s with no clients; exiting")
            exit(0)
        }
        timer.resume()
        idleTimer = timer
    }

    private func cancelIdleExit() {
        idleTimer?.cancel()
        idleTimer = nil
    }
}
