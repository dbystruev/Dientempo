import AVFoundation
import Foundation

@MainActor
final class SpanishNumberSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private enum WarmUpState {
        case idle
        case warming
        case ready
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let selectedVoice: AVSpeechSynthesisVoice?
    private var warmUpState = WarmUpState.idle
    private var warmUpContinuations: [CheckedContinuation<Void, Never>] = []
    private var warmUpTimeoutTask: Task<Void, Never>?

    override init() {
        selectedVoice = Self.bestInstalledSpanishVoice()
        super.init()
        synthesizer.delegate = self
    }

    func prepare() {
        startWarmUpIfNeeded()
    }

    func prepareForCounting() async {
        switch warmUpState {
        case .ready:
            return
        case .idle:
            startWarmUpIfNeeded()
        case .warming:
            break
        }

        await withCheckedContinuation { continuation in
            warmUpContinuations.append(continuation)
        }
    }

    func speak(number: Int) {
        let words = SpanishNumberFormatter.words(for: number)
        let utterance = utterance(for: words)

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func rate(for words: String) -> Float {
        let length = Float(words.count)
        let normalized = min(max((length - 4) / 22, 0), 1)
        return 0.48 + normalized * 0.14
    }

    private func startWarmUpIfNeeded() {
        guard warmUpState == .idle else { return }

        warmUpState = .warming

        let utterance = utterance(for: SpanishNumberFormatter.words(for: 0))
        utterance.volume = 0
        synthesizer.speak(utterance)

        warmUpTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.completeWarmUp()
        }
    }

    private func completeWarmUpIfNeeded() {
        guard warmUpState == .warming else { return }
        completeWarmUp()
    }

    private func completeWarmUp() {
        guard warmUpState != .ready else { return }

        warmUpTimeoutTask?.cancel()
        warmUpTimeoutTask = nil
        warmUpState = .ready

        let continuations = warmUpContinuations
        warmUpContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func utterance(for words: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = selectedVoice
        utterance.rate = rate(for: words)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        return utterance
    }

    private static func bestInstalledSpanishVoice() -> AVSpeechSynthesisVoice? {
        let spanishVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("es")
        }

        return spanishVoices.max { lhs, rhs in
            isVoice(lhs, lowerPriorityThan: rhs)
        } ?? AVSpeechSynthesisVoice(language: "es-ES")
            ?? AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es-US")
    }

    private static func isVoice(_ lhs: AVSpeechSynthesisVoice, lowerPriorityThan rhs: AVSpeechSynthesisVoice) -> Bool {
        let lhsQuality = lhs.quality.rawValue
        let rhsQuality = rhs.quality.rawValue
        if lhsQuality != rhsQuality {
            return lhsQuality < rhsQuality
        }

        let lhsLocale = localeRank(for: lhs.language)
        let rhsLocale = localeRank(for: rhs.language)
        if lhsLocale != rhsLocale {
            return lhsLocale < rhsLocale
        }

        return lhs.identifier > rhs.identifier
    }

    private static func localeRank(for language: String) -> Int {
        switch language {
        case "es-ES":
            return 3
        case "es-MX":
            return 2
        case "es-US":
            return 1
        default:
            return 0
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }
}
