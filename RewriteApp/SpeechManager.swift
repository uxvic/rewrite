import Foundation
import AVFoundation
import Speech
import AppKit

/// Live voice-to-text using Apple's Speech framework. Transcribed text is
/// published as it comes in so the UI can stream it into the input box.
@MainActor
final class SpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Toggles dictation. Resolves authorization on first use.
    func toggle() {
        if isRecording {
            stop()
        } else {
            requestAuthorizationThenStart()
        }
    }

    private func requestAuthorizationThenStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.start()
                case .denied, .restricted:
                    self.errorMessage = "Speech recognition permission was denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
                case .notDetermined:
                    self.errorMessage = "Speech recognition not yet authorized."
                @unknown default:
                    self.errorMessage = "Speech recognition unavailable."
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available right now."
            return
        }

        errorMessage = nil
        transcript = ""
        playChime("Tink")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        let wasRecording = isRecording
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        if wasRecording { playChime("Pop") }
    }

    private func playChime(_ name: String) {
        guard AppSettings.shared.recordingSounds else { return }
        NSSound(named: name)?.play()
    }
}
