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
    /// Smoothed mic amplitude 0…1, for the reactive strands + waveform.
    @Published var level: Float = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Text from recognition segments that have already finalized. The live
    /// `transcript` is always `committed` + the current segment's partial, so a
    /// pause (which finalizes a segment) never clears earlier dictation.
    private var committed = ""
    /// Guards against a tight restart loop if the recognizer keeps failing with
    /// no new speech in between.
    private var emptyRestarts = 0

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

    /// Starts a fresh, user-initiated dictation session (clears any prior text).
    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available right now."
            return
        }

        errorMessage = nil
        committed = ""
        transcript = ""
        emptyRestarts = 0
        playChime("Tink")

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.updateLevel(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        isRecording = true
        beginTask()
    }

    /// Starts a recognition request + task on the already-running audio engine.
    /// Used for the first segment and to resume after a pause/finalize, so
    /// dictation keeps going until the user explicitly stops. The mic tap appends
    /// to `self.request`, so swapping the request needs no re-tap.
    private func beginTask() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep dictation fully on-device when the recognizer supports it (true on
        // macOS 14+ for en-US), so transcription never leaves the Mac.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }

                if let result {
                    let partial = result.bestTranscription.formattedString
                    self.transcript = self.committed.isEmpty
                        ? partial
                        : (partial.isEmpty ? self.committed : self.committed + " " + partial)
                    if !partial.isEmpty { self.emptyRestarts = 0 }
                }

                // A finalized segment (pause/silence or the ~1-min on-device cap) or
                // a benign error ends THIS request, not the session: fold the segment
                // into `committed` and listen again so earlier dictation is kept.
                if (result?.isFinal ?? false) || error != nil {
                    self.committed = self.transcript
                    self.request?.endAudio()
                    self.request = nil
                    self.task = nil
                    // Repeated failures with no new words → recognizer is likely
                    // unavailable; stop instead of spinning.
                    if error != nil && self.transcript.isEmpty {
                        self.emptyRestarts += 1
                        if self.emptyRestarts >= 3 {
                            self.errorMessage = "Dictation stopped unexpectedly. Try again."
                            self.stop()
                            return
                        }
                    }
                    self.beginTask()
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
        level = 0
        if wasRecording { playChime("Pop") }
    }

    /// Computes a smoothed amplitude from the live mic buffer (audio thread → main).
    nonisolated private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { let s = ch[i]; sum += s * s }
        let rms = (sum / Float(n)).squareRoot()
        let mapped = min(1, rms * 18)
        Task { @MainActor in self.level = self.level * 0.7 + mapped * 0.3 }
    }

    private func playChime(_ name: String) {
        guard AppSettings.shared.recordingSounds else { return }
        NSSound(named: name)?.play()
    }
}
