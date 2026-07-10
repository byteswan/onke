import Foundation
import Combine

/// The observable bridge between a `PowerSourceProviding` and the SwiftUI panel.
///
/// For this first vertical slice it owns a provider, starts sampling, and republishes the
/// latest ``PowerSample`` for the UI to render. Rolling-window rate/time-remaining
/// (spec §5.1) and the notification engine (spec §5.3) slot in here later — this type is
/// the single place that turns raw samples into everything the app shows.
@MainActor
final class MetricsEngine: ObservableObject {

    /// Most recent reading, or `nil` before the first sample arrives.
    @Published private(set) var sample: PowerSample?

    private let provider: PowerSourceProviding
    private let interval: TimeInterval

    init(provider: PowerSourceProviding, interval: TimeInterval = 5) {
        self.provider = provider
        self.interval = interval
    }

    func start() {
        provider.start(interval: interval) { [weak self] sample in
            // FakePowerSource already delivers on the main queue; hop to the main actor
            // to satisfy isolation and stay correct for other providers.
            Task { @MainActor in self?.sample = sample }
        }
    }

    func stop() {
        provider.stop()
    }
}
