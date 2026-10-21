


import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - Settings (saved between launches)
final class SpeechSettings: ObservableObject {
    @Published var rate: Double { didSet { UserDefaults.standard.set(rate, forKey: "sh.rate") } }
    @Published var detailed: Bool { didSet { UserDefaults.standard.set(detailed, forKey: "sh.detailed") } }

    init() {
        let saved = UserDefaults.standard.double(forKey: "sh.rate")
        rate = saved == 0 ? 0.48 : saved
        detailed = UserDefaults.standard.bool(forKey: "sh.detailed")
    }
}

// MARK: - Speaker
final class Speaker {
    private let synth = AVSpeechSynthesizer()

    init() {
        // playAndRecord so speaking and voice commands can coexist
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func speak(_ text: String, rate: Double) {
        guard !text.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(rate)
        synth.speak(utterance)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

// MARK: - Voice commands
enum VoiceCommand {
    case describe, read, repeatLast, stop, faster, slower

    static func match(_ text: String) -> VoiceCommand? {
        let t = text.lowercased()
        if t.contains("stop") || t.contains("quiet") { return .stop }
        if t.contains("read") { return .read }
        if t.contains("describe") || t.contains("what") || t.contains("look") { return .describe }
        if t.contains("repeat") || t.contains("again") { return .repeatLast }
        if t.contains("faster") { return .faster }
        if t.contains("slower") { return .slower }
        return nil
    }
}

final class VoiceListener: ObservableObject {
    @Published var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func listen(onCommand: @escaping (VoiceCommand) -> Void) {
        guard !isListening else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async { self.begin(onCommand) }
            }
        }
    }

    private func begin(_ onCommand: @escaping (VoiceCommand) -> Void) {
        guard let recognizer, recognizer.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { return }
        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result, let cmd = VoiceCommand.match(result.bestTranscription.formattedString) {
                DispatchQueue.main.async {
                    guard self.isListening else { return }
                    self.finish()
                    onCommand(cmd)
                }
            } else if error != nil {
                DispatchQueue.main.async { self.finish() }
            }
        }

        // Stop listening after 7 seconds if nothing was recognized
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
