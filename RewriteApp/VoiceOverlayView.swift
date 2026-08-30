import SwiftUI

/// Dictation as a single floating glass card hanging right under the menu-bar
/// icon: live transcript (glowing softly as words land), an amplitude-driven
/// waveform, and trash+Esc / Use ⏎ controls. No strands, no top animation —
/// just the card, like the reference.
struct VoiceOverlayView: View {
    @ObservedObject var speech: SpeechManager
    var onDone: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var transcriptHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            recordingCard
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .frame(width: 424, height: 700, alignment: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    // MARK: Recording card

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            transcript
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack(spacing: 7) {
                        Image(systemName: "trash").font(.system(size: 12.5))
                        Text("Esc").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Discard dictation")

                waveform.frame(maxWidth: .infinity)

                Button(action: onDone) {
                    HStack(spacing: 7) {
                        Text("Use").font(.system(size: 13, weight: .semibold))
                        Text("⏎").font(.system(size: 12, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("Use this text")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(RoundedRectangle(cornerRadius: 30, style: .continuous), shadow: 0.35)
        // A restrained violet bloom behind the glass — the "recording" light. It
        // breathes slowly (static under Reduce Motion) and stays tight to the
        // card so it never reads as a stray artifact.
        .background {
            RadialGradient(colors: [Theme.accent.opacity(0.38), Theme.accent.opacity(0)],
                           center: .center, startRadius: 8, endRadius: 190)
                .blur(radius: 24)
                .scaleEffect(breathe ? 1.05 : 0.97)
                .padding(-20)          // stays inside the window's 22pt gutter — no clipping
                .allowsHitTesting(false)
        }
        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 4)
    }

    // MARK: Transcript

    /// Exactly as tall as the words (one line while listening), up to a cap —
    /// then it scrolls, pinned to the newest words.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                transcriptText
                    .font(.system(size: 17.5, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The words glow softly as they land.
                    .shadow(color: Theme.accent.opacity(0.6), radius: 10)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ThreadHeightKey.self, value: g.size.height)
                    })
                Color.clear.frame(height: 1).id("bottom")
            }
            .onPreferenceChange(ThreadHeightKey.self) { transcriptHeight = $0 }
            .frame(height: min(max(transcriptHeight, 26), 116))
            .onChange(of: speech.transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// Transcript text with a live caret while recording.
    private var transcriptText: Text {
        let base = Text(displayText).foregroundColor(transcriptColor)
        if speech.isRecording && speech.errorMessage == nil {
            return base + Text(" ▏").foregroundColor(Theme.accent)
        }
        return base
    }

    private var displayText: String {
        if let err = speech.errorMessage { return err }
        return speech.transcript.isEmpty ? "Listening…" : speech.transcript
    }
    private var transcriptColor: Color {
        if speech.errorMessage != nil { return Theme.ledFail }
        return speech.transcript.isEmpty ? Theme.textSecondary : Theme.textPrimary
    }

    // MARK: Waveform

    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let lvl = CGFloat(min(max(speech.level, 0), 1))
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    let wave = (sin(t * 6 + Double(i) * 0.5) + 1) / 2     // 0…1
                    let h = 3 + CGFloat(wave) * (4 + lvl * 22)
                    Capsule()
                        .fill(Color.white.opacity(0.55 + Double(lvl) * 0.45))
                        .frame(width: 2.5, height: h)
                }
            }
            .frame(height: 30)
            .frame(maxWidth: .infinity)
        }
    }
}
