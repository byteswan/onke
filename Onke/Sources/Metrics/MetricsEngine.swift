import Foundation
import Combine

/// The observable bridge between a `PowerSourceProviding` and the SwiftUI panel.
///
/// It owns a provider, starts sampling, and turns each raw ``PowerSample`` into the
/// derived state the app shows: the sample itself plus the smoothed rate / time-remaining
/// from ``RateEstimator``. This is the single place raw samples become everything the UI
/// and (later) the notification engine consume.
@MainActor
final class MetricsEngine: ObservableObject {

    /// Most recent reading, or `nil` before the first sample arrives.
    @Published private(set) var sample: PowerSample?

    /// Smoothed rate / time-remaining derived from the rolling window.
    @Published private(set) var rate: RateEstimator.Output =
        RateEstimator.Output(ratePercentPerHour: nil, timeRemaining: nil, isWarmedUp: false)

    /// The connected power adapter's details (name, watts, maker…), or nil on battery.
    /// Refreshed each sample from the public `IOPSCopyExternalPowerAdapterDetails` API.
    @Published private(set) var adapter: PowerAdapter?

    private let provider: PowerSourceProviding
    private let interval: TimeInterval
    private var estimator: RateEstimator

    /// Fires on every new sample, after `sample`/`rate` have been updated. The
    /// notification engine subscribes here.
    let didSample = PassthroughSubject<(PowerSample, RateEstimator.Output), Never>()

    init(provider: PowerSourceProviding, interval: TimeInterval = 5) {
        self.provider = provider
        self.interval = interval
        self.estimator = RateEstimator(expectedInterval: interval)
    }

    func start() {
        provider.start(interval: interval) { [weak self] sample in
            // Providers may deliver off the main queue; hop to the main actor.
            Task { @MainActor in self?.handle(sample) }
        }
    }

    func stop() {
        provider.stop()
    }

    private func handle(_ sample: PowerSample) {
        let output = estimator.ingest(sample)
        self.sample = sample
        self.rate = output
        // Only query the adapter when something's plugged in; nil on battery.
        self.adapter = sample.externalConnected ? PowerAdapter.current : nil
        didSample.send((sample, output))
    }
}
