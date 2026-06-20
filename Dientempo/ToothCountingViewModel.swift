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
    private var countingTimer: DispatchSourceTimer?
    private var activeSessionID = UUID()

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

        cancelCountingTimer()
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
        cancelCountingTimer()
        activeSessionID = UUID()
        speaker.stop()
        speaker.releaseAudioSession()
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
        cancelCountingTimer()
        state = .running
        let sessionID = UUID()
        activeSessionID = sessionID

        speaker.prepareForCounting { [weak self] in
            guard let self else { return }
            self.beginCounting(from: firstNumber, sessionID: sessionID)
        }
    }

    private func beginCounting(from firstNumber: Int, sessionID: UUID) {
        guard state == .running, activeSessionID == sessionID else { return }

        let startTime = DispatchTime.now()
        announce(number: firstNumber)
        scheduleNextTick(number: firstNumber + 1, firstNumber: firstNumber, startTime: startTime, sessionID: sessionID)
    }

    private func scheduleNextTick(number: Int, firstNumber: Int, startTime: DispatchTime, sessionID: UUID) {
        guard state == .running, activeSessionID == sessionID else { return }

        let elapsedCount = number - firstNumber
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: startTime + .seconds(elapsedCount), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .running, self.activeSessionID == sessionID else { return }

            if number <= Self.targetNumber {
                self.announce(number: number)
                self.scheduleNextTick(number: number + 1, firstNumber: firstNumber, startTime: startTime, sessionID: sessionID)
            } else {
                self.finish()
            }
        }

        countingTimer = timer
        timer.resume()
    }

    private func announce(number: Int) {
        currentNumber = number
        speaker.speak(number: number)
    }

    private func finish() {
        cancelCountingTimer()
        speaker.stop()
        speaker.releaseAudioSession()
        currentNumber = Self.targetNumber
        state = .finished
    }

    private func cancelCountingTimer() {
        countingTimer?.setEventHandler {}
        countingTimer?.cancel()
        countingTimer = nil
    }
}
