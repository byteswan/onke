import Foundation
import Combine
import ServiceManagement

/// App-side manager for the privileged helper (spec §6.1): owns registration via
/// `SMAppService.daemon`, the XPC connection, and the stream of per-process energy
/// snapshots. Publishes both the daemon's approval state (so the UI can guide the user)
/// and the latest aggregated per-app energy list.
@MainActor
final class HelperClient: NSObject, ObservableObject, HelperClientProtocol {

    /// Where the helper stands from the app's point of view — drives the per-app UI's
    /// explainer states (spec §6.2).
    enum State: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case failed(String)
    }

    @Published private(set) var state: State = .notRegistered
    /// Aggregated top apps by energy impact, most-hungry first. Unitless (spec §6.2).
    @Published private(set) var topApps: [AppEnergy] = []

    private let plistName = "com.byteswan.onke.helper.plist"
    private var connection: NSXPCConnection?
    private let decoder = JSONDecoder()

    private var service: SMAppService { SMAppService.daemon(plistName: plistName) }

    // MARK: Registration

    func refreshState() {
        switch service.status {
        case .notRegistered: state = .notRegistered
        case .requiresApproval: state = .requiresApproval
        case .enabled: state = .enabled
        @unknown default: state = .notRegistered
        }
    }

    /// Register the daemon (first use of per-app features). On macOS 13 this may return
    /// `.requiresApproval`, in which case the user must enable it in System Settings; we
    /// surface that state and offer to open the pane.
    func enable() {
        do {
            try service.register()
            refreshState()
            if state == .enabled { connect() }
        } catch {
            // A common case: needs approval in System Settings > General > Login Items.
            refreshState()
            if state != .requiresApproval {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: XPC connection

    func connect() {
        guard connection == nil else { return }
        let conn = NSXPCConnection(machServiceName: onkeHelperMachServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: HelperClientProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        conn.resume()
        connection = conn

        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.state = .failed(error.localizedDescription) }
        } as? HelperProtocol
        proxy?.subscribe { _ in /* version handshake ignored for now */ }
    }

    func disconnect() {
        (connection?.remoteObjectProxy as? HelperProtocol)?.unsubscribe()
        connection?.invalidate()
        connection = nil
    }

    /// A proxy for one-shot helper commands (Low Power Mode, Wi-Fi fallback — spec §7.2).
    /// Establishes the connection on demand; returns nil if the helper isn't enabled.
    func helperProxy() -> HelperProtocol? {
        guard state == .enabled else { return nil }
        if connection == nil { connect() }
        return connection?.remoteObjectProxyWithErrorHandler { _ in } as? HelperProtocol
    }

    // MARK: HelperClientProtocol (helper → app)

    nonisolated func receiveSnapshot(_ snapshotJSON: Data) {
        guard let snapshot = try? JSONDecoder().decode(EnergySnapshot.self, from: snapshotJSON)
        else { return }
        let aggregated = AppEnergy.aggregate(snapshot.processes)
        Task { @MainActor in self.topApps = Array(aggregated.prefix(8)) }
    }
}
