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
    private var isSpeakerAudioSessionActive = false
    private var isRenderingWarmUp = false
    private var pendingReplacementUtterance: AVSpeechUtterance?
    private var speakCompletion: (() -> Void)?

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
        activateSpeakerAudioSession()

        if isSelectedVoiceWarm {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                completion()
            }
            return
        }

        warmUpCompletions.append(completion)
        startWarmUpIfNeeded()
    }

    func speak(number: Int, completion: (() -> Void)? = nil) {
        activateSpeakerAudioSession()

        let words = SpanishNumberFormatter.words(for: number)
        let utterance = utterance(for: words)
        debugAudio("Speaker speak number=\(number) words=\"\(words)\" wasSpeaking=\(synthesizer.isSpeaking)")

        if synthesizer.isSpeaking {
            pendingReplacementUtterance = utterance
            speakCompletion = completion
            debugAudio("Speaker interrupt previous utterance before number=\(number); replacement pending")
            synthesizer.stopSpeaking(at: .immediate)
            speakPendingReplacementIfIdle()
            return
        }

        speakCompletion = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        pendingReplacementUtterance = nil
        speakCompletion = nil
        guard synthesizer.isSpeaking else { return }
        debugAudio("Speaker stop current utterance")
        synthesizer.stopSpeaking(at: .immediate)
    }

    func releaseAudioSession() {
        guard isSpeakerAudioSessionActive else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSpeakerAudioSessionActive = false
            debugAudio("Speaker audio session deactivated")
        } catch {
            debugAudio("Speaker audio session deactivation failed: \(error)")
        }
    }

    private func speakPendingReplacementIfIdle() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.synthesizer.isSpeaking, let utterance = self.pendingReplacementUtterance else { return }

            self.pendingReplacementUtterance = nil
            self.debugAudio("Speaker speak pending replacement utterance=\"\(utterance.speechString)\"")
            self.synthesizer.speak(utterance)
        }
    }

    private func rate(for words: String) -> Float {
        let length = Float(words.count)
        let normalized = min(max((length - 4) / 22, 0), 1)
        return 0.55 + normalized * 0.10
    }

    private func startWarmUpIfNeeded() {
        guard !isSelectedVoiceWarm else { return }
        guard warmUpState != .warming else { return }

        warmUpState = .warming
        warmingVoiceIdentifier = selectedVoice?.identifier
        #if DEBUG
        debugAudio(SpanishVoicePreference.debugSelectionSummary())
        #endif
        debugAudio("Speaker warm-up starting voice=\(warmingVoiceIdentifier ?? "none")")

        let utterance = utterance(for: SpanishNumberFormatter.words(for: 0))
        isRenderingWarmUp = true
        // Render and discard one utterance to load the selected voice without audible warm-up.
        synthesizer.write(utterance) { [weak self] buffer in
            guard let self, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
            if pcmBuffer.frameLength > 0 {
                return
            }
            self.debugAudio("Speaker warm-up render complete")
            DispatchQueue.main.async {
                self.isRenderingWarmUp = false
                self.completeWarmUpIfNeeded()
            }
        }
    }

    private func completeWarmUpIfNeeded() {
        guard warmUpState == .warming else { return }
        completeWarmUp()
    }

    private func completeWarmUp() {
        guard warmUpState != .ready else { return }

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
            isSpeakerAudioSessionActive = true
            debugAudio("Speaker audio session activated")
        } catch {
            debugAudio("Speaker audio session activation failed: \(error)")
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        SpanishVoicePreference.selectedVoice()
    }

    private var isSelectedVoiceWarm: Bool {
        warmUpState == .ready && warmedVoiceIdentifier == selectedVoice?.identifier
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if isRenderingWarmUp {
            debugAudio("Speaker warm-up render didStart word=\"\(utterance.speechString)\"")
            return
        }

        debugAudio("Speaker didStart utterance=\"\(utterance.speechString)\" volume=\(utterance.volume)")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isRenderingWarmUp {
            isRenderingWarmUp = false
            DispatchQueue.main.async { [weak self] in
                self?.completeWarmUpIfNeeded()
            }
            return
        }

        debugAudio("Speaker didFinish utterance=\"\(utterance.speechString)\"")

        let completion = speakCompletion
        speakCompletion = nil
        DispatchQueue.main.async {
            completion?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if isRenderingWarmUp {
            isRenderingWarmUp = false
            DispatchQueue.main.async { [weak self] in
                self?.completeWarmUpIfNeeded()
            }
            return
        }

        debugAudio("Speaker didCancel utterance=\"\(utterance.speechString)\"")

        if let pendingReplacementUtterance {
            self.pendingReplacementUtterance = nil
            debugAudio("Speaker speak canceled replacement utterance=\"\(pendingReplacementUtterance.speechString)\"")
            synthesizer.speak(pendingReplacementUtterance)
            return
        }

        let completion = speakCompletion
        speakCompletion = nil
        DispatchQueue.main.async {
            completion?()
        }
    }

    private func debugAudio(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[DientempoAudio] %@", message())
        #endif
    }
}
