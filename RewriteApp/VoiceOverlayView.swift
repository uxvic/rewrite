import SwiftUI

/// Dictation as a floating, GLOWING glass card at the bottom of the transparent
/// surface: the reactive strands above, then the card with the live transcript,
/// an amplitude-driven waveform, and Esc / Use ⏎ controls. The violet bloom +
/// colored shadow make the recording state unmistakable.
struct VoiceOverlayView: View {
    @ObservedObject var speech: SpeechManager
    var onDone: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            strands
            recordingCard
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 380, height: 668)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    // MARK: Strands

    /// Flowing, glowing strands that swell while the user talks — floating
    /// straight over the desktop now (the window has no background at all).
    private var strands: some View {
        StrandsView(
            colors: ["#A7A4F5", "#8E8BF0", "#C5C2FA"],
            count: 3, speed: 0.5, amplitude: 1, waviness: 1,
            thickness: 0.7, glow: 2.0, taper: 3, spread: 1,
            hueShift: 0, intensity: 0.5, saturation: 1.2, opacity: 1, scale: 1.5,
            level: speech.level
        )
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding(.horizontal, -16)
        .allowsHitTesting(false)
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
        // The colored bloom radiating out from behind the glass — the "recording"
        // light. It breathes slowly (static under Reduce Motion).
        .background {
            RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)],
                           center: .center, startRadius: 8, endRadius: 230)
                .blur(radius: 28)
                .scaleEffect(breathe ? 1.08 : 0.97)
                .padding(-46)
                .allowsHitTesting(false)
        }
        .shadow(color: Theme.accent.opacity(0.45), radius: 30, y: 4)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                transcriptText
                    .font(.system(size: 17.5, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The words themselves glow as they land.
                    .shadow(color: Theme.accent.opacity(0.7), radius: 12)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 28)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(maxHeight: 130)
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
