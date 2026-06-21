import SwiftUI

/// Full-popover voice-capture takeover: reactive flowing strands, live
/// transcript, and an amplitude-driven waveform. Reuses the app's design tokens.
struct VoiceOverlayView: View {
    @ObservedObject var speech: SpeechManager
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.bg

            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                strands
                Spacer()
                transcript
                Spacer()
                waveformPill
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)

            // Esc cancels.
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
        }
        .frame(width: 380, height: 668)
        .onDisappear { speech.stop() }   // safety: never leave the mic running
    }

    // MARK: Strands

    /// Flowing, glowing strands that swell while the user talks. The web view is
    /// transparent and the strands fade out at the edges, so they blend straight
    /// into the overlay background — no card, no border. Full-bleed across the
    /// window (cancels the parent's horizontal padding).
    private var strands: some View {
        StrandsView(
            colors: ["#F97316", "#7C3AED", "#06B6D4"],
            count: 3, speed: 0.5, amplitude: 1, waviness: 1,
            thickness: 0.7, glow: 2.6, taper: 3, spread: 1,
            hueShift: 0, intensity: 0.6, saturation: 2, opacity: 1, scale: 1.5,
            level: speech.level
        )
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .padding(.horizontal, -24)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                transcriptText
                    .font(.system(size: 20, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(maxHeight: 200)
            .onChange(of: speech.transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// Transcript text with a live acid caret while recording.
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

    // MARK: Waveform pill

    private var waveformPill: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.panel))
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            }.buttonStyle(.plain).help("Cancel")

            waveform.frame(maxWidth: .infinity)

            Button(action: onDone) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.accent))
            }.buttonStyle(.plain).help("Use this text")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }

    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let lvl = CGFloat(min(max(speech.level, 0), 1))
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let wave = (sin(t * 6 + Double(i) * 0.5) + 1) / 2     // 0…1
                    let h = 4 + CGFloat(wave) * (4 + lvl * 26)
                    Capsule()
                        .fill(Theme.accent.opacity(0.45 + Double(lvl) * 0.55))
                        .frame(width: 3, height: h)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
        }
    }
}
