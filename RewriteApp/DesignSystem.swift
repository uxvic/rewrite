import SwiftUI
import AppKit

// MARK: - Hex + dynamic colors

extension NSColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v & 0xFF0000) >> 16) / 255
        let g = CGFloat((v & 0x00FF00) >> 8) / 255
        let b = CGFloat(v & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// A color that resolves differently for light vs dark appearance.
    static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

/// "Apple Intelligence" design tokens — soft, near-black surfaces, a muted
/// lavender accent, translucent fills. Dark is the showcase; light is supported.
enum Theme {
    static let bg            = Color(nsColor: .dynamic(light: "#F2F2F7", dark: "#0B0B0F"))
    /// Lighter top stop for the ambient radial-gradient background.
    static let bgGradientTop = Color(nsColor: .dynamic(light: "#FFFFFF", dark: "#1A1820"))
    static let surface   = Color(nsColor: .dynamic(light: "#FFFFFF", dark: "#17171C"))
    static let panel     = Color(nsColor: .dynamic(light: "#FFFFFF", dark: "#1E1E25"))
    static let hairline  = Color(nsColor: .dynamic(light: "#E2E2EA", dark: "#2A2A33"))
    static let textPrimary   = Color(nsColor: .dynamic(light: "#1A1A1F", dark: "#F2F3F7"))
    static let textSecondary = Color(nsColor: .dynamic(light: "#6E6E78", dark: "#9A9AA6"))
    static let nsTextPrimary = NSColor.dynamic(light: "#1A1A1F", dark: "#F2F3F7")

    /// Muted lavender / periwinkle accent, used sparingly.
    static let accent    = Color(nsColor: .dynamic(light: "#7C78E8", dark: "#A7A4F5"))
    /// Ink on top of an accent-filled element. Dynamic so it stays readable: white
    /// on the deeper light-mode accent, dark on the pale dark-mode lavender (the
    /// old pure-white failed contrast on the light lavender).
    static let accentInk = Color(nsColor: .dynamic(light: "#FFFFFF", dark: "#1B1726"))
    static let ledFail   = Color(nsColor: .dynamic(light: "#E5483B", dark: "#FF6B5E"))

    /// White in dark mode, black in light mode. Apply at a low opacity so the
    /// translucent button/icon fills invert correctly between appearances.
    static let fillTranslucent = Color(nsColor: .dynamic(light: "#000000", dark: "#FFFFFF"))
}

enum Metric {
    static let radius: CGFloat = 18
    static let buttonRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let bubbleRadius: CGFloat = 24
    static let field: CGFloat = 14
    static let window: CGFloat = 12
}

// MARK: - Fonts (SF Pro)

extension Font {
    static func monoLabel(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .semibold) }
    static func mono(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func display(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .bold) }
}

// MARK: - Components

/// A soft section header (SF Pro, light tracking).
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textSecondary
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).tracking(0.3).foregroundStyle(color)
    }
}

struct HairlineDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 1) }
}

/// Small bordered keycap, e.g. ⌘1.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Soft status dot with a gentle glow.
struct LEDDot: View {
    var color: Color = Theme.accent
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

/// Soft capsule button: prominent = accent fill + white ink; otherwise a subtle
/// translucent fill with a faint border.
struct InstrumentButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Theme.accentInk : Theme.textPrimary)
            .padding(.vertical, 8).padding(.horizontal, 16)
            .background(Capsule().fill(prominent ? Theme.accent : Theme.fillTranslucent.opacity(0.06)))
            .overlay {
                if !prominent { Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Circular, translucent icon button — the Siri X / mic / + style.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 34
    /// Accent-filled (e.g. send / confirm).
    var prominent: Bool = false
    /// Soft accent tint (e.g. an active panel).
    var active: Bool = false
    var disabled: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(prominent ? Theme.accentInk : (active ? Theme.accent : Theme.textPrimary))
                .frame(width: size, height: size)
                .background {
                    // Floating Big Sur glass: frosted material (or accent when
                    // prominent), a soft drop shadow so it lifts off the chat.
                    ZStack {
                        if prominent {
                            Circle().fill(Theme.accent)
                        } else {
                            Circle().fill(.regularMaterial)
                            if active { Circle().fill(Theme.accent.opacity(0.20)) }
                        }
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
                }
                .overlay {
                    if !prominent {
                        Circle().stroke(Theme.fillTranslucent.opacity(0.10), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
    }
}

/// Near-black ambient background with a subtle radial lift toward the top.
struct AmbientBackground: View {
    var body: some View {
        RadialGradient(gradient: Gradient(colors: [Theme.bgGradientTop, Theme.bg]),
                       center: .top, startRadius: 0, endRadius: 540)
            .ignoresSafeArea()
    }
}

/// A glass / vibrant text-field pill ("Ask Siri" style).
struct CapsuleFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1))
    }
}

extension View {
    /// A soft, translucent "card" surface (rounded fill + faint border + shadow).
    func module(_ fillColor: Color = Theme.surface, focused: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .stroke(focused ? Theme.accent.opacity(0.6) : Theme.fillTranslucent.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
    }

    /// Near-black ambient radial background.
    func ambientBackground() -> some View { background(AmbientBackground()) }

    /// Translucent stand-in for `.module` on glass surfaces — a quiet tinted
    /// card that lets the glass behind it show through instead of an opaque slab.
    func glassModule(focused: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
            .fill(Theme.fillTranslucent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
            .stroke(focused ? Theme.accent.opacity(0.6) : Theme.fillTranslucent.opacity(0.08), lineWidth: 1))
    }

    /// Big Sur–style frosted glass for a floating control: an opaque-ish material
    /// fill in `shape`, a hairline edge, and a soft drop shadow so it reads as
    /// floating above the chat scrolling behind it.
    func glassFloat<S: Shape>(_ shape: S, stroke: Double = 0.10, shadow: Double = 0.20) -> some View {
        background(shape.fill(.regularMaterial).shadow(color: Color.black.opacity(shadow), radius: 6, y: 2))
            .overlay(shape.stroke(Theme.fillTranslucent.opacity(stroke), lineWidth: 1))
    }

    /// Liquid glass for the background-less popover: on macOS 26+ (Tahoe) this is
    /// the REAL system Liquid Glass (`.glassEffect`) — true refraction of whatever
    /// is behind the window. On older macOS (and older build toolchains) it falls
    /// back to the closest hand-built approximation: ultra-thin material, a top
    /// light-catch, and a soft lift shadow. Every floating element wears this.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, shadow: Double = 0.30) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                // Deep near-black smoke under the real glass — genuine Liquid Glass
                // refracts the pixels behind the window, so this keeps it glassy
                // BLACK (piano-black) rather than washing to the desktop's colour.
                .background(shape.fill(Color.black.opacity(0.5)))
                .glassEffect(.regular, in: shape)
                .overlay(glossSheen(shape))
                .shadow(color: Color.black.opacity(shadow), radius: 14, y: 6)
        } else {
            approximateGlass(shape, shadow: shadow)
        }
        #else
        approximateGlass(shape, shadow: shadow)
        #endif
    }

    /// The pre-Tahoe stand-in for liquid glass. A deep near-black smoke over the
    /// material gives the glossy-black body; the sheen + rim make it read as
    /// reflective glass (piano black) rather than flat dark paint.
    private func approximateGlass<S: Shape>(_ shape: S, shadow: Double) -> some View {
        background(
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.6)))
                .shadow(color: Color.black.opacity(shadow), radius: 14, y: 6)
        )
        .overlay(glossSheen(shape))
        .overlay(
            shape.stroke(
                LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
    }

    /// A glossy top-light on the dark glass — a bright reflection fading from the
    /// top edge, blended additively so it reads as a sheen on black glass (the
    /// piano-black / plastic look) rather than a grey overlay.
    private func glossSheen<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0),
                    .init(color: Color.white.opacity(0.04), location: 0.30),
                    .init(color: .clear, location: 0.62),
                ],
                startPoint: .top, endPoint: .bottom))
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
