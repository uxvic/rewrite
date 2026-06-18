import SwiftUI

/// Native recreation of the reactbits.dev "Strands" effect: a set of flowing,
/// glowing, tapered ribbons that wave horizontally across the canvas. The
/// `level` (0…1, smoothed mic amplitude) drives reactivity so the strands
/// swell and brighten while the user talks. Pure SwiftUI `Canvas` — no WebGL,
/// no dependencies — so it stays at home in the menu-bar app.
struct StrandsView: View {
    /// Palette spread across the strands (the reactbits `colors` prop).
    var colors: [Color] = [
        Color(nsColor: NSColor(hex: "#F97316")),   // orange
        Color(nsColor: NSColor(hex: "#7C3AED")),   // violet
        Color(nsColor: NSColor(hex: "#06B6D4"))    // cyan
    ]
    var count: Int = 3
    var speed: Double = 0.5
    var amplitude: Double = 1
    var waviness: Double = 1
    var thickness: Double = 0.7
    var glow: Double = 2.6
    var taper: Double = 3
    var spread: Double = 1
    var intensity: Double = 0.6
    var scale: Double = 1.5
    /// Smoothed mic amplitude 0…1. Drives swell, speed, and brightness.
    var level: Float = 0

    private let samples = 96

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: t)
            }
        }
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let h = Double(size.height)
        let w = Double(size.width)
        let lvl = Double(min(max(level, 0), 1))

        // Idle strands breathe gently; talking makes them swell and quicken.
        let amp      = amplitude * scale * h * 0.13 * (0.45 + lvl * 0.95)
        let spreadPx = spread * scale * h * 0.11
        let halfCore = thickness * scale * 7.0 * (0.85 + lvl * 0.5)
        let glowR    = halfCore * glow
        let flow     = time * speed * (0.8 + lvl * 0.6)
        let bright   = intensity * (0.7 + lvl * 0.6)

        // Additive blending so overlapping glows read as light on the dark panel.
        ctx.blendMode = .plusLighter

        let n = max(count, 1)
        for i in 0..<n {
            let color = strandColor(i)
            let phase = Double(i) * 1.7
            let baseY = h / 2 + Double(i) * spreadPx - Double(n - 1) * spreadPx / 2

            let ribbon = ribbonPath(width: w, baseY: baseY, half: halfCore,
                                    amp: amp, phase: phase, flow: flow)
            let core   = ribbonPath(width: w, baseY: baseY, half: halfCore * 0.4,
                                    amp: amp, phase: phase, flow: flow)

            // Soft outer halo.
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: CGFloat(glowR)))
                g.fill(ribbon, with: .color(color.opacity(0.45 * bright)))
            }
            // Tighter inner glow.
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: CGFloat(glowR * 0.4)))
                g.fill(ribbon, with: .color(color.opacity(0.65 * bright)))
            }
            // Hot near-white filament down the centre.
            ctx.fill(core, with: .color(mix(color, .white, 0.6).opacity(min(1, 0.85 * bright + 0.15))))
        }
    }

    /// Builds a tapered ribbon polygon: a wavy centre-line offset up and down by
    /// an envelope that is fat in the middle and pinched to a point at each end.
    private func ribbonPath(width: Double, baseY: Double, half: Double,
                            amp: Double, phase: Double, flow: Double) -> Path {
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        top.reserveCapacity(samples + 1)
        bottom.reserveCapacity(samples + 1)

        for s in 0...samples {
            let u = Double(s) / Double(samples)            // 0…1 along the strand
            let x = u * width
            let wave = sin(2 * .pi * waviness * u + flow + phase)
                     + 0.5 * sin(2 * .pi * waviness * 1.9 * u + flow * 1.4 + phase * 1.7)
            let y = baseY + amp * wave
            let env = pow(sin(.pi * u), taper)             // taper envelope, 0 at ends
            let dy = half * env
            top.append(CGPoint(x: x, y: y - dy))
            bottom.append(CGPoint(x: x, y: y + dy))
        }

        var path = Path()
        path.move(to: top[0])
        for p in top.dropFirst() { path.addLine(to: p) }
        for p in bottom.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    // MARK: Colour helpers

    /// Strand `i`'s colour, interpolated across the palette.
    private func strandColor(_ i: Int) -> Color {
        guard colors.count > 1 else { return colors.first ?? .white }
        let t = count > 1 ? Double(i) / Double(count - 1) : 0
        let pos = t * Double(colors.count - 1)
        let lo = Int(pos)
        let hi = min(lo + 1, colors.count - 1)
        return mix(colors[lo], colors[hi], pos - Double(lo))
    }

    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        let f = CGFloat(min(max(t, 0), 1))
        return Color(nsColor: NSColor(
            srgbRed: na.redComponent + (nb.redComponent - na.redComponent) * f,
            green: na.greenComponent + (nb.greenComponent - na.greenComponent) * f,
            blue: na.blueComponent + (nb.blueComponent - na.blueComponent) * f,
            alpha: 1))
    }
}
