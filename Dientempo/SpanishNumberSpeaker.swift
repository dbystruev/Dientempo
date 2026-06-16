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
    private var warmUpState = WarmUpState.idle
    private var warmedVoiceIdentifier: String?
    private var warmingVoiceIdentifier: String?
    private var warmUpContinuations: [CheckedContinuation<Void, Never>] = []
    private var warmUpTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func prepare() {
        startWarmUpIfNeeded()
    }

    func prepareForCounting() async {
        if isSelectedVoiceWarm {
            return
        }

        startWarmUpIfNeeded()

        await withCheckedContinuation { continuation in
            warmUpContinuations.append(continuation)
        }
    }

    func speak(number: Int) {
        activateSpeakerAudioSession()

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
        guard !isSelectedVoiceWarm else { return }
        guard warmUpState != .warming else { return }

        activateSpeakerAudioSession()

        warmUpState = .warming
        warmingVoiceIdentifier = selectedVoice?.identifier

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
        warmedVoiceIdentifier = warmingVoiceIdentifier
        warmingVoiceIdentifier = nil

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

    private func activateSpeakerAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            // Speech should still be attempted if route setup fails.
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        SpanishVoicePreference.selectedVoice()
    }

    private var isSelectedVoiceWarm: Bool {
        warmUpState == .ready && warmedVoiceIdentifier == selectedVoice?.identifier
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
