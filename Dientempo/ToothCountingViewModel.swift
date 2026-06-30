import Foundation

@MainActor
final class ToothCountingViewModel: ObservableObject {
    enum SessionState: Equatable {
        case ready
        case running
        case paused
        case finished
    }

    static let targetNumber = 200

    @Published private(set) var currentNumber = 0
    @Published private(set) var state: SessionState = .ready
    @Published private(set) var isWarmingUp = true

    private let speaker = SpanishNumberSpeaker()
    private var activeSessionID = UUID()
    private var sessionStartTime: Date?
    private var lastNumberSpokenTime: Date?

    private var lastSwipeTime: Date?
    private var swipeDirection: Int?
    private var swipeStreak = 0

    var isRunning: Bool {
        state == .running
    }

    var isCounting: Bool {
        state == .running || state == .paused
    }

    var currentWords: String {
        SpanishNumberFormatter.words(for: currentNumber)
    }

    func prepareSpeech() {
        isWarmingUp = true
        speaker.prepareForCounting { [weak self] in
            self?.isWarmingUp = false
        }
    }

    func start() {
        guard !isRunning else { return }

        currentNumber = 0
        resetSwipeStreak()
        startCounting(from: currentNumber)
    }

    func pauseForInterruption() {
        guard isRunning else { return }

        activeSessionID = UUID()
        speaker.stop()
        speaker.releaseAudioSession()
        state = .paused
    }

    func resumeAfterInterruption() {
        guard state == .paused else { return }

        startCounting(from: currentNumber)
    }

    func stop() {
        activeSessionID = UUID()
        speaker.stop()
        speaker.releaseAudioSession()
        logSessionDuration()
        currentNumber = 0
        state = .ready
        resetSwipeStreak()
    }

    func togglePause() {
        switch state {
        case .running:
            pauseForInterruption()
        case .paused:
            resumeAfterInterruption()
        case .ready:
            startCounting(from: currentNumber)
        case .finished:
            break
        }
    }

    func move(by offset: Int) {
        guard offset != 0 else { return }

        let now = Date()
        let isContinuation = swipeDirection == offset
            && lastSwipeTime != nil
            && now.timeIntervalSince(lastSwipeTime!) < 0.5

        if isContinuation {
            swipeStreak += 1
        } else {
            swipeStreak = 1
            swipeDirection = offset
        }

        lastSwipeTime = now

        let delta = swipeDelta(for: swipeStreak)
        let adjustedOffset = offset * delta
        let nextNumber = min(Self.targetNumber, max(0, currentNumber + adjustedOffset))
        guard nextNumber != currentNumber else { return }

        currentNumber = nextNumber
        startCounting(from: nextNumber)
    }

    private func swipeDelta(for streak: Int) -> Int {
        switch streak {
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 4: return 5
        case 5: return 8
        case 6: return 12
        default: return 16
        }
    }

    private func resetSwipeStreak() {
        swipeStreak = 0
        swipeDirection = nil
        lastSwipeTime = nil
    }

    private func startCounting(from firstNumber: Int) {
        activeSessionID = UUID()
        state = .running
        lastNumberSpokenTime = Date()
        let sessionID = activeSessionID

        speaker.prepareForCounting { [weak self] in
            guard let self else { return }
            self.sessionStartTime = Date().addingTimeInterval(-TimeInterval(firstNumber))
            self.speakNumber(firstNumber, sessionID: sessionID)
        }
    }

    private func speakNumber(_ number: Int, sessionID: UUID) {
        guard state == .running, activeSessionID == sessionID else { return }

        currentNumber = number

        let now = Date()
        let expectedTime = sessionStartTime!.addingTimeInterval(TimeInterval(number))
        let delay = now.timeIntervalSince(expectedTime)
        let words = SpanishNumberFormatter.words(for: number)
        let adjustedRate = speaker.rateForWords(words, delay: delay)

        debugLog("speak number=\(number) delay=\(String(format: "%.2f", delay))s rate=\(String(format: "%.2f", adjustedRate))")

        lastNumberSpokenTime = now
        speaker.speak(number: number, rate: adjustedRate) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.state == .running, self.activeSessionID == sessionID else { return }

                if number < Self.targetNumber {
                    self.speakNumber(number + 1, sessionID: sessionID)
                } else {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        speaker.stop()
        speaker.releaseAudioSession()
        logSessionDuration()
        currentNumber = Self.targetNumber
        state = .finished
    }

    private func logSessionDuration() {
        guard let startTime = sessionStartTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        debugLog(String(format: "session duration=%.1fs for %d numbers (%.2fs avg)", duration, currentNumber + 1, duration / Double(currentNumber + 1)))
        sessionStartTime = nil
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        NSLog("[DientempoCount] %@", message)
        #endif
    }
}
