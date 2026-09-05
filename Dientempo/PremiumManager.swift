import Foundation
import Combine

/// Tracks whether the user has unlocked unlimited access, and enforces the
/// free-tier limit of one counting session per calendar day.
///
/// `canRun` and `timeRemaining()` are deliberately both anchored to calendar
/// midnight (not "24 hours since the last run") so the lock screen's countdown
/// always agrees with when the app actually unlocks again.
@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    // MARK: - Published state

    /// true when the user has bought the unlimited-access purchase.
    @Published private(set) var isPremiumUnlocked: Bool = false

    // MARK: - Keys

    private let defaults = UserDefaults.standard
    private let lastRunDateKey = "dientempo.lastRunDate"
    private let premiumKey = "dientempo.isPremiumUnlocked"

    // MARK: - Init

    private init() {
        isPremiumUnlocked = defaults.bool(forKey: premiumKey)
    }

    // MARK: - Availability

    /// Returns true when the app is allowed to start a new counting session.
    var canRun: Bool {
        isPremiumUnlocked || !ranToday()
    }

    private func ranToday() -> Bool {
        guard let lastRun = defaults.object(forKey: lastRunDateKey) as? Date else {
            return false
        }
        return Calendar.current.isDate(lastRun, inSameDayAs: Date())
    }

    // MARK: - Countdown

    /// Seconds until the app unlocks again (next calendar midnight). Zero when
    /// already allowed to run. Kept in lockstep with `canRun`'s own notion of
    /// "today" -- both use `Calendar.current` -- so the displayed countdown
    /// never disagrees with the actual unlock moment.
    func timeRemaining() -> TimeInterval {
        guard !canRun else { return 0 }

        let calendar = Calendar.current
        let now = Date()
        guard let startOfNextDay = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return 0
        }

        return max(0, startOfNextDay.timeIntervalSince(now))
    }

    /// Human-readable countdown string, e.g. "18:34:12".
    func countdownString() -> String {
        let t = timeRemaining()
        let hours = Int(t) / 3600
        let minutes = (Int(t) % 3600) / 60
        let seconds = Int(t) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Recording a run

    /// Call ONCE when a brand-new session actually starts (see
    /// `ToothCountingViewModel.onSessionWillStart`). Do not call this from UI
    /// button handlers directly -- multiple gestures can start a session, and
    /// wiring this to only one of them re-opens the daily-limit bypass this
    /// class exists to close.
    func recordRun() {
        defaults.set(Date(), forKey: lastRunDateKey)
    }

    // MARK: - Premium unlock

    /// Called after a successful purchase or restore.
    func unlockPremium() {
        isPremiumUnlocked = true
        defaults.set(true, forKey: premiumKey)
    }

    // MARK: - Reset (for testing only)

    /// Clears premium and last-run date so the lock screen can be re-tested.
    func resetForTesting() {
        isPremiumUnlocked = false
        defaults.set(false, forKey: premiumKey)
        defaults.removeObject(forKey: lastRunDateKey)
    }
}
