import Foundation

@MainActor
final class ToothCountingViewModel: ObservableObject {
    enum SessionState {
        case ready
        case running
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

    var currentWords: String {
        SpanishNumberFormatter.words(for: currentNumber)
    }

    func prepareSpeech() {
        speaker.prepare()
    }

    func start() {
        guard !isRunning else { return }

        countingTask?.cancel()
        currentNumber = 0
        state = .running

        countingTask = Task { [weak self] in
            guard let self else { return }

            await speaker.prepareForCounting()
            guard !Task.isCancelled else { return }

            let startTime = clock.now

            for number in 0...Self.targetNumber {
                guard !Task.isCancelled else { return }

                currentNumber = number
                speaker.speak(number: number)

                let nextDeadline = startTime.advanced(by: .seconds(number + 1))

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

    func stop() {
        countingTask?.cancel()
        countingTask = nil
        speaker.stop()
        currentNumber = 0
        state = .ready
    }

    private func finish() {
        countingTask = nil
        speaker.stop()
        currentNumber = Self.targetNumber
        state = .finished
    }
}
