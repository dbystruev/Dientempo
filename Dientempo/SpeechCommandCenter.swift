import AVFoundation
import Foundation
import Speech

enum SpeechCommand {
    case start
    case stop
}

final class SpeechCommandCenter: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var commandHandler: ((SpeechCommand) -> Void)?
    private var shouldListen = false
    private var lastTranscript = ""
    private var lastCommandDate = Date.distantPast

    func start(commandHandler: @escaping (SpeechCommand) -> Void) {
        self.commandHandler = commandHandler
        guard !shouldListen else { return }

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
        guard let recognizer, recognizer.isAvailable else {
            scheduleRestart()
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            shouldListen = false
            return
        }

        stopRecognition()

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
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
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
                DispatchQueue.main.async {
                    self.stopRecognition()
                    self.scheduleRestart()
                }
            }
        }
    }

    private func stopRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
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
}

private extension String {
    var normalizedForCommandMatching: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
