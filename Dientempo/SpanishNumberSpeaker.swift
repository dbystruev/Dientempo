@preconcurrency import AVFoundation
import Foundation

final class SpanishNumberSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private enum WarmUpState {
        case idle
        case warming
        case ready
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var warmUpState = WarmUpState.idle
    private var warmedVoiceIdentifier: String?
    private var warmingVoiceIdentifier: String?
    private var warmUpCompletions: [() -> Void] = []
    private var warmUpTimeoutWorkItem: DispatchWorkItem?
    private var isSpeakerAudioSessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func prepare() {
        startWarmUpIfNeeded()
    }

    func prepareForCounting(_ completion: @escaping () -> Void) {
        if isSelectedVoiceWarm {
            completion()
            return
        }

        warmUpCompletions.append(completion)
        startWarmUpIfNeeded()
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

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.completeWarmUp()
        }
        warmUpTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700), execute: timeoutWorkItem)
    }

    private func completeWarmUpIfNeeded() {
        guard warmUpState == .warming else { return }
        completeWarmUp()
    }

    private func completeWarmUp() {
        guard warmUpState != .ready else { return }

        warmUpTimeoutWorkItem?.cancel()
        warmUpTimeoutWorkItem = nil
        warmUpState = .ready
        warmedVoiceIdentifier = warmingVoiceIdentifier
        warmingVoiceIdentifier = nil

        let completions = warmUpCompletions
        warmUpCompletions.removeAll()
        completions.forEach { $0() }
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
        guard !isSpeakerAudioSessionActive else { return }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
            isSpeakerAudioSessionActive = true
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }
}
