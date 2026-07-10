import Foundation
import Combine
import UserNotifications

/// Turns the sample stream into local notifications (spec §5.3). Maintains the rolling
/// state each rule needs (10-min watts-out average, sustained-condition timers), evaluates
/// all five rules per sample, and posts the results.
///
/// The evaluation is split out into ``NotificationEvaluator`` (pure, no OS calls) so the
/// hysteresis/anti-spam behaviour can be unit-tested; this class is the thin shell that
/// subscribes to the engine and talks to `UNUserNotificationCenter`.
@MainActor
final class NotificationEngine {

    private let settings: AppSettings
    private var evaluator = NotificationEvaluator()
    private var cancellables: Set<AnyCancellable> = []
    private let post: (PowerNotification) -> Void

    init(settings: AppSettings,
         post: @escaping (PowerNotification) -> Void = NotificationEngine.postToSystem) {
        self.settings = settings
        self.post = post
    }

    /// Ask for permission once, then subscribe to the metrics stream. If a `helper` is
    /// provided, the drain-spike rule is fed the current top energy offender so its
    /// notification body can name the culprit (spec §6.2).
    func attach(to engine: MetricsEngine, helper: HelperClient? = nil) {
        requestAuthorizationIfNeeded()
        engine.didSample.sink { [weak self] sample, rate in
            self?.consume(sample: sample, rate: rate)
        }.store(in: &cancellables)

        helper?.$topApps.sink { [weak self] apps in
            self?.evaluator.topOffender = apps.first?.name
        }.store(in: &cancellables)
    }

    private func consume(sample: PowerSample, rate: RateEstimator.Output) {
        guard settings.notificationsEnabled else { return }
        let ctx = evaluator.makeContext(
            sample: sample, rate: rate,
            timeLowMinutes: settings.timeLowMinutes,
            timeLowRearmMinutes: settings.timeLowRearmMinutes,
            drainSpikeMultiplier: settings.drainSpikeMultiplier)
        for note in evaluator.evaluate(ctx) {
            post(note)
        }
    }

    // MARK: Permission

    private func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: Posting

    static func postToSystem(_ note: PowerNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        // Reuse the rule id as the request id so a repeat of the same event replaces the
        // prior banner instead of stacking.
        let request = UNNotificationRequest(identifier: note.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Pure notification logic: owns the rules and the rolling state they depend on, with no
/// dependency on UserNotifications or wall-clock side effects. Fully unit-testable by
/// feeding it a scripted `(sample, rate)` sequence.
struct NotificationEvaluator {

    private let drainSpikeRule = DrainSpikeRule()
    private let rules: [NotificationRule]

    init() {
        rules = [
            TimeRemainingLowRule(),
            drainSpikeRule,
            WeakPowerbankRule(),
            UnplugAtFullRule(),
            LevelWarningRule(),
        ]
    }

    /// Name of the current top energy offender, surfaced in the drain-spike body (§6.2).
    var topOffender: String? {
        get { drainSpikeRule.topOffender }
        nonmutating set { drainSpikeRule.topOffender = newValue }
    }

    // Rolling 10-min average of watts-out, as an EMA to avoid storing a buffer.
    private var avgWattsOut: Double = 0
    private var hasAvg = false

    // Sustained-condition timers.
    private var spikeSince: Date?
    private var weakSince: Date?

    /// Assemble the context for the current sample, updating rolling state.
    mutating func makeContext(sample: PowerSample, rate: RateEstimator.Output,
                              timeLowMinutes: Double, timeLowRearmMinutes: Double,
                              drainSpikeMultiplier: Double,
                              now: Date? = nil) -> RuleContext {
        let now = now ?? sample.timestamp
        let wattsOut = max(0, -sample.netWatts)

        // 10-min EMA over ~5s samples ⇒ small alpha.
        let alpha = 1.0 / (600.0 / 5.0)
        if hasAvg {
            avgWattsOut += alpha * (wattsOut - avgWattsOut)
        } else {
            avgWattsOut = wattsOut
            hasAvg = true
        }

        // Track how long the spike / weak conditions have held continuously.
        let ratio = avgWattsOut > 0.01 ? wattsOut / avgWattsOut : 0
        if ratio >= drainSpikeMultiplier {
            spikeSince = spikeSince ?? now
        } else if ratio < 1.2 {
            spikeSince = nil
        }
        if sample.isPluggedButDraining {
            weakSince = weakSince ?? now
        } else {
            weakSince = nil
        }

        return RuleContext(
            sample: sample, rate: rate,
            avgWattsOut: avgWattsOut,
            sustainedSpike: spikeSince.map { now.timeIntervalSince($0) } ?? 0,
            sustainedWeak: weakSince.map { now.timeIntervalSince($0) } ?? 0,
            now: now,
            timeLowMinutes: timeLowMinutes,
            timeLowRearmMinutes: timeLowRearmMinutes,
            drainSpikeMultiplier: drainSpikeMultiplier)
    }

    func evaluate(_ ctx: RuleContext) -> [PowerNotification] {
        rules.compactMap { $0.evaluate(ctx) }
    }
}
