import AVFoundation
import CoreAudio
import Foundation
import Speech

enum SpeechCommand {
    case start
    case stop
}

final class SpeechCommandCenter: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var commandHandler: ((SpeechCommand) -> Void)?
    private var shouldListen = false
    private var lastTranscript = ""
    private var lastCommandDate = Date.distantPast
    private var isRecognitionAudioSessionActive = false

    func start(commandHandler: @escaping (SpeechCommand) -> Void) {
        self.commandHandler = commandHandler
        guard !shouldListen else { return }

        Self.debugAudio("SpeechCommandCenter.start")
        shouldListen = true

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard speechStatus == .authorized else { return }

            self?.requestMicrophonePermission { granted in
                guard granted else { return }

                DispatchQueue.main.async {
                    self?.beginRecognition()
                }
            }
        }
    }

    func stop() {
        guard shouldListen || audioEngine.isRunning || recognitionRequest != nil || recognitionTask != nil else { return }

        Self.debugAudio("SpeechCommandCenter.stop")
        shouldListen = false
        stopRecognition()
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    private func beginRecognition() {
        guard shouldListen, recognitionTask == nil else { return }

        switch Self.onDeviceRecognizer() {
        case let .ready(recognizer):
            startRecognition(with: recognizer)
        case .temporarilyUnavailable:
            Self.debugAudio("On-device speech recognizer temporarily unavailable; scheduling restart")
            scheduleRestart()
        case .unsupported:
            Self.debugAudio("No on-device speech recognizer available for \(Self.recognitionLocaleIdentifiers.joined(separator: ", "))")
            shouldListen = false
        }
    }

    private func startRecognition(with recognizer: SFSpeechRecognizer) {
        stopRecognition()
        Self.debugAudio("Speech recognition starting locale=\(recognizer.locale.identifier)")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = [
            "vamos",
            "go",
            "inicia",
            "iniciar",
            "empieza",
            "empezar",
            "comienza",
            "comenzar",
            "alto",
            "para",
            "pare",
            "detente",
            "detener",
            "stop"
        ]
        recognitionRequest = request
        lastTranscript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isRecognitionAudioSessionActive = true

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                guard buffer.frameLength > 0, Self.hasAudioData(in: buffer) else { return }
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            Self.debugAudio("Speech audio engine started")
        } catch {
            Self.debugAudio("Speech recognition failed to start: \(error)")
            stopRecognition()
            scheduleRestart()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.handle(transcript: result.bestTranscription.formattedString)
            }

            if error != nil || result?.isFinal == true {
                if let error {
                    Self.debugAudio("Speech recognition ended with error: \(error)")
                } else {
                    Self.debugAudio("Speech recognition ended")
                }

                DispatchQueue.main.async {
                    self.stopRecognition()
                    self.scheduleRestart()
                }
            }
        }
    }

    private func stopRecognition() {
        guard audioEngine.isRunning || recognitionRequest != nil || recognitionTask != nil else { return }
        Self.debugAudio("Speech recognition stopping")

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        deactivateRecognitionAudioSession()
    }

    private func deactivateRecognitionAudioSession() {
        guard isRecognitionAudioSessionActive else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isRecognitionAudioSessionActive = false
            Self.debugAudio("Speech recognition audio session deactivated")
        } catch {
            Self.debugAudio("Speech recognition audio session deactivation failed: \(error)")
        }
    }

    private static func hasAudioData(in buffer: AVAudioPCMBuffer) -> Bool {
        guard buffer.frameLength > 0 else { return false }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard !audioBuffers.isEmpty else { return false }

        return audioBuffers.allSatisfy { audioBuffer in
            audioBuffer.mData != nil && audioBuffer.mDataByteSize > 0
        }
    }

    private static func onDeviceRecognizer() -> RecognizerSelection {
        var hasTemporarilyUnavailableRecognizer = false

        for identifier in recognitionLocaleIdentifiers {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
                debugAudio("Speech recognizer unavailable for locale=\(identifier)")
                continue
            }

            guard recognizer.supportsOnDeviceRecognition else {
                debugAudio("On-device speech recognition unsupported for locale=\(identifier)")
                continue
            }

            guard recognizer.isAvailable else {
                debugAudio("On-device speech recognition unavailable now for locale=\(identifier)")
                hasTemporarilyUnavailableRecognizer = true
                continue
            }

            return .ready(recognizer)
        }

        return hasTemporarilyUnavailableRecognizer ? .temporarilyUnavailable : .unsupported
    }

    private static var recognitionLocaleIdentifiers: [String] {
        uniqueIdentifiers([
            SpanishVoicePreference.selectedVoice()?.language,
            "es-ES",
            "es-MX",
            "es-US",
            "en-US"
        ])
    }

    private static func uniqueIdentifiers(_ identifiers: [String?]) -> [String] {
        var seenIdentifiers = Set<String>()

        return identifiers.compactMap { identifier in
            guard let identifier, !seenIdentifiers.contains(identifier) else { return nil }

            seenIdentifiers.insert(identifier)
            return identifier
        }
    }

    private func scheduleRestart() {
        guard shouldListen else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.beginRecognition()
        }
    }

    private func handle(transcript: String) {
        let normalized = transcript.normalizedForCommandMatching
        guard normalized != lastTranscript else { return }
        lastTranscript = normalized

        guard let command = Self.command(in: normalized) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastCommandDate) > 1 else { return }
        lastCommandDate = now

        DispatchQueue.main.async { [commandHandler] in
            commandHandler?(command)
        }
    }

    private static func command(in text: String) -> SpeechCommand? {
        if containsAnyStopCommand(in: text) {
            return .stop
        }

        if containsAnyStartCommand(in: text) {
            return .start
        }

        return nil
    }

    private static func containsAnyStartCommand(in text: String) -> Bool {
        commandWords(["go", "vamos", "inicia", "iniciar", "empieza", "empezar", "comienza", "comenzar", "dale"], appearIn: text)
    }

    private static func containsAnyStopCommand(in text: String) -> Bool {
        commandWords(["stop", "alto", "para", "pare", "detente", "detener", "basta"], appearIn: text)
    }

    private static func commandWords(_ words: [String], appearIn text: String) -> Bool {
        let tokens = Set(text.split(separator: " ").map(String.init))
        return words.contains { tokens.contains($0) }
    }

    private static func debugAudio(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[DientempoAudio] %@", message())
        #endif
    }
}

private enum RecognizerSelection {
    case ready(SFSpeechRecognizer)
    case temporarilyUnavailable
    case unsupported
}

private extension String {
    var normalizedForCommandMatching: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
