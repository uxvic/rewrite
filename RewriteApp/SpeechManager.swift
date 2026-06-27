import Foundation
import AVFoundation
import Speech
import AppKit

/// Live voice-to-text using Apple's Speech framework. Transcribed text is
/// published as it comes in so the UI can stream it into the input box.
///
/// Continuity across pauses: the on-device `SFSpeechRecognizer` does NOT report
/// `isFinal` when the speaker pauses — it silently *resets* its running
/// transcription in place, so the next partial contains only the post-pause
/// words. To avoid clearing earlier dictation we keep a monotonic `committed`
/// buffer and, whenever we detect that reset, fold the prior phrase into it
/// before the new partial overwrites the live segment. Only the user pressing
/// Done (`stop()`) finalizes; text is never lost except on a brand-new session.
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

    /// Text from segments that are already locked in (a prior request finalized,
    /// or we detected the recognizer reset its hypothesis on a pause). Only grows
    /// until the user stops.
    private var committed = ""
    /// The current request's live transcription. `transcript` is always
    /// `committed` joined with `segment`. `formattedString` always REPLACES this
    /// (never appends), so in-place word revisions ("their"→"there") are clean.
    private var segment = ""
    /// Bumped on every `beginTask()`. A recognition callback captures its
    /// generation and bails if it no longer matches, so a stale callback from a
    /// superseded/cancelled task can never corrupt the live request's state.
    private var generation = 0
    /// Consecutive recognition errors with no recognized words; caps restarts so
    /// a persistently failing recognizer can't spin forever.
    private var errorRestarts = 0

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
        segment = ""
        transcript = ""
        errorRestarts = 0
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
    /// Used for the first segment and to resume after the ~1-min on-device cap or
    /// an error, so dictation continues until the user explicitly stops. The mic
    /// tap appends to `self.request`, so swapping the request needs no re-tap.
    private func beginTask() {
        guard let recognizer else { return }

        // Supersede any previous request/task. Bumping the generation first means
        // a late callback from the old task sees a stale generation and bails,
        // so cancelling here can't race the new request's state.
        generation &+= 1
        let myGeneration = generation
        task?.cancel()
        request?.endAudio()
        request = nil
        task = nil
        segment = ""

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
                guard let self, self.isRecording, myGeneration == self.generation else { return }

                if let result {
                    let incoming = result.bestTranscription.formattedString
                    // The on-device recognizer resets its hypothesis in place after
                    // a pause (no isFinal): the partial drops to a fresh utterance
                    // that no longer overlaps what we had. Fold the prior phrase
                    // into `committed` BEFORE adopting the new one, so a pause never
                    // erases earlier dictation.
                    if self.isReset(prev: self.segment, next: incoming) {
                        self.foldSegment()
                    }
                    self.segment = incoming
                    self.transcript = self.joinedTranscript()
                    if !incoming.isEmpty { self.errorRestarts = 0 }
                }

                // A real final result (e.g. the ~1-min cap) or an error ends THIS
                // request, not the session: lock in what we have and listen again.
                if (result?.isFinal ?? false) || error != nil {
                    self.foldSegment()
                    if error != nil {
                        self.errorRestarts += 1
                        if self.errorRestarts >= 4 {
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
        // Lock in any in-flight words BEFORE teardown so pressing Done never drops
        // the last partial. Bump the generation so trailing callbacks bail.
        if wasRecording {
            generation &+= 1
            foldSegment()
            transcript = committed
        }
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

    // MARK: - Segment accumulation

    /// `committed` joined with the live `segment`, single space only when both
    /// sides are non-empty.
    private func joinedTranscript() -> String {
        if committed.isEmpty { return segment }
        if segment.isEmpty { return committed }
        return committed + " " + segment
    }

    /// Locks the current `segment` into `committed` and clears it. Idempotent, and
    /// skips a re-fold of identical text so a double call can't duplicate.
    private func foldSegment() {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        segment = ""
        guard !trimmed.isEmpty else { return }
        if committed == trimmed || committed.hasSuffix(" " + trimmed) {
            transcript = committed
            return
        }
        committed = committed.isEmpty ? trimmed : committed + " " + trimmed
        transcript = committed
    }

    /// Is `next` a fresh utterance (the recognizer reset) rather than a revision
    /// or extension of `prev`? Growth/in-place revisions share a prefix or keep
    /// most words; a reset drops to empty or to words that barely overlap. Word-
    /// overlap (not raw length / first-word) avoids false positives on revisions
    /// like "their car is" → "there car is fast", which would otherwise duplicate.
    private func isReset(prev: String, next: String) -> Bool {
        let p = prev.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        let n = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return true }
        if n.hasPrefix(p) || p.hasPrefix(n) { return false }   // growth or revision
        let prevWords = p.lowercased().split(separator: " ")
        guard prevWords.count >= 2 else { return false }       // single word → just a revision
        let nextWords = Set(n.lowercased().split(separator: " "))
        let overlap = prevWords.filter { nextWords.contains($0) }.count
        return Double(overlap) / Double(prevWords.count) < 0.5
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
