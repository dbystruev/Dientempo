import Foundation

@MainActor
final class ToothCountingViewModel: ObservableObject {
    enum SessionState {
        case ready
        case running
        case paused
        case finished
    }

    static let targetNumber = 200

    @Published private(set) var currentNumber = 0
    @Published private(set) var state: SessionState = .ready

    private let speaker = SpanishNumberSpeaker()
    private let clock = ContinuousClock()
    private var countingTask: Task<Void, Never>?

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
        speaker.prepare()
    }

    func start() {
        guard !isRunning else { return }

        currentNumber = 0
        startCounting(from: currentNumber)
    }

    func pauseForInterruption() {
        guard isRunning else { return }

        countingTask?.cancel()
        countingTask = nil
        speaker.stop()
        state = .paused
    }

    func resumeAfterInterruption() {
        guard state == .paused else { return }

        startCounting(from: currentNumber)
    }

    func stop() {
        countingTask?.cancel()
        countingTask = nil
        speaker.stop()
        currentNumber = 0
        state = .ready
    }

    func togglePause() {
        switch state {
        case .running:
            pauseForInterruption()
        case .paused:
            resumeAfterInterruption()
        case .ready, .finished:
            break
        }
    }

    func move(by offset: Int) {
        guard offset != 0 else { return }

        let nextNumber = min(Self.targetNumber, max(0, currentNumber + offset))
        guard nextNumber != currentNumber else { return }

        currentNumber = nextNumber
        startCounting(from: nextNumber)
    }

    private func startCounting(from firstNumber: Int) {
        countingTask?.cancel()
        state = .running

        countingTask = Task { [weak self] in
            guard let self else { return }

            await speaker.prepareForCounting()
            guard !Task.isCancelled else { return }

            let startTime = clock.now

            for number in firstNumber...Self.targetNumber {
                guard !Task.isCancelled else { return }

                currentNumber = number
                speaker.speak(number: number)

                let elapsedCount = number - firstNumber + 1
                let nextDeadline = startTime.advanced(by: .seconds(elapsedCount))

                do {
                    try await clock.sleep(until: nextDeadline, tolerance: .milliseconds(2))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        countingTask = nil
        speaker.stop()
        currentNumber = Self.targetNumber
        state = .finished
    }
}
