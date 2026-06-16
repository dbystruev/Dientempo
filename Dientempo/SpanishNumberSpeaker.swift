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
        debugAudio("Speaker prepare")
        startWarmUpIfNeeded()
    }

    func prepareForCounting(_ completion: @escaping () -> Void) {
        debugAudio("Speaker prepareForCounting warm=\(isSelectedVoiceWarm)")

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
        debugAudio("Speaker speak number=\(number) words=\"\(words)\" wasSpeaking=\(synthesizer.isSpeaking)")

        if synthesizer.isSpeaking {
            debugAudio("Speaker interrupt previous utterance before number=\(number)")
            synthesizer.stopSpeaking(at: .immediate)
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        debugAudio("Speaker stop current utterance")
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
        #if DEBUG
        debugAudio(SpanishVoicePreference.debugSelectionSummary())
        #endif
        debugAudio("Speaker warm-up starting voice=\(warmingVoiceIdentifier ?? "none")")

        let utterance = utterance(for: SpanishNumberFormatter.words(for: 0))
        // Render and discard one utterance to load the selected voice without audible warm-up.
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength == 0 else { return }

            DispatchQueue.main.async {
                self?.completeWarmUpIfNeeded()
            }
        }

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
        debugAudio("Speaker warm-up complete voice=\(warmedVoiceIdentifier ?? "none")")

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
            debugAudio("Speaker audio session activated")
        } catch {
            debugAudio("Speaker audio session activation failed: \(error)")
            // Speech should still be attempted if route setup fails.
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        SpanishVoicePreference.selectedVoice()
    }

    private var isSelectedVoiceWarm: Bool {
        warmUpState == .ready && warmedVoiceIdentifier == selectedVoice?.identifier
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        debugAudio("Speaker didStart utterance=\"\(utterance.speechString)\" volume=\(utterance.volume)")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        debugAudio("Speaker didFinish utterance=\"\(utterance.speechString)\"")

        DispatchQueue.main.async { [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        debugAudio("Speaker didCancel utterance=\"\(utterance.speechString)\"")

        DispatchQueue.main.async { [weak self] in
            self?.completeWarmUpIfNeeded()
        }
    }

    private func debugAudio(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[DientempoAudio] %@", message())
        #endif
    }
}
