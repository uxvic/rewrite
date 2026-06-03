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

/// "Industrial Instrument" design tokens — acid accent, graphite (dark) / concrete (light).
enum Theme {
    static let bg        = Color(nsColor: .dynamic(light: "#E9EAE6", dark: "#0E0F11"))
    static let surface   = Color(nsColor: .dynamic(light: "#F4F4F1", dark: "#16181B"))
    static let panel     = Color(nsColor: .dynamic(light: "#FFFFFF", dark: "#1C1F23"))
    static let hairline  = Color(nsColor: .dynamic(light: "#D4D5CF", dark: "#2C3035"))
    static let textPrimary   = Color(nsColor: .dynamic(light: "#15171A", dark: "#F3F5F6"))
    static let textSecondary = Color(nsColor: .dynamic(light: "#6A6E72", dark: "#878D94"))

    static let accent    = Color(nsColor: NSColor(hex: "#CBFF2E"))
    static let accentInk  = Color(nsColor: NSColor(hex: "#0E0F0E"))
    static let ledFail   = Color(nsColor: NSColor(hex: "#FF4D3D"))
}

enum Metric {
    static let radius: CGFloat = 4
    static let buttonRadius: CGFloat = 6
    static let window: CGFloat = 12
}

// MARK: - Fonts

extension Font {
    static func monoLabel(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
    static func mono(_ size: CGFloat = 11) -> Font { .system(size: size, design: .monospaced) }
    static func display(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }
}

// MARK: - Components

/// Mono uppercase tracked section label (e.g. INPUT / ACTIONS / OUTPUT).
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textSecondary
    var body: some View {
        Text(text).font(.monoLabel(10)).tracking(1.6).foregroundStyle(color)
    }
}

struct HairlineDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// Small bordered keycap, e.g. ⌘1.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.mono(9)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.hairline, lineWidth: 1))
    }
}

struct LEDDot: View {
    var color: Color = Theme.accent
    var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
}

/// Instrument button: prominent = acid fill; otherwise hairline outline.
struct InstrumentButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.monoLabel(11)).tracking(1)
            .foregroundStyle(prominent ? Theme.accentInk : Theme.textPrimary)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: Metric.radius).fill(prominent ? Theme.accent : Color.clear))
            .overlay(prominent ? nil : RoundedRectangle(cornerRadius: Metric.radius).stroke(Theme.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// A bordered "module" surface (panel fill + hairline border).
    func module(_ fillColor: Color = Theme.surface, focused: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: Metric.radius).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: Metric.radius)
                .stroke(focused ? Theme.accent : Theme.hairline, lineWidth: 1))
    }
}
