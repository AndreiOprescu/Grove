import SwiftUI
import AppKit

extension Color {
    /// Hex like 0xF3EEE3.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that follows light and dark mode.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    init(_ tone: Tone) {
        self.init(light: tone.light, dark: tone.dark, lightAlpha: tone.lightAlpha, darkAlpha: tone.darkAlpha)
    }
}

/// Colour, font and shape tokens of one theme (PLAN §6). Built from a `ThemeSpec`.
struct Theme: Identifiable {
    var kind: ThemeID
    var id: String { kind.rawValue }
    var name: String
    var bg: Color
    var surface: Color
    var surface2: Color
    var ink: Color
    var muted: Color
    var accent: Color
    var accent2: Color
    var accent3: Color
    var line: Color
    var blobs: [Color]
    var blobOpacity: Double
    var radius: CGFloat

    // Personality (PLAN §6.2)
    /// Panels are Liquid Glass (Futuristic).
    var glass: Bool { kind == .futuristic }
    /// Square check boxes (Futuristic, Vintage).
    var squareChecks: Bool { kind == .futuristic || kind == .vintage }
    /// Paper noise and a vignette (Vintage).
    var paper: Bool { kind == .vintage }
    /// Faint 32 pt grid lines on the background (Futuristic).
    var gridLines: Bool { kind == .futuristic }
    /// Headings in capitals with wide spacing and a glow (Futuristic).
    var upperHeadings: Bool { kind == .futuristic }
    /// Thin borders and no shadows (Minimal).
    var hairlines: Bool { kind == .minimal }
    /// Neon glow on the now line and check boxes (Futuristic).
    var glow: Bool { kind == .futuristic }
    /// Dashed borders on chips (Vintage).
    var dashedChips: Bool { kind == .vintage }
    /// Lines under the text of a note (Vintage), as tall as one line.
    var ruledLines: Bool { kind == .vintage }
    /// The ink stamp on a finished task (Vintage).
    var stampOnDone: Bool { kind == .vintage }

    init(_ spec: ThemeSpec) {
        kind = spec.id
        name = spec.name
        bg = Color(spec.bg); surface = Color(spec.surface); surface2 = Color(spec.surface2)
        ink = Color(spec.ink); muted = Color(spec.muted)
        accent = Color(spec.accent); accent2 = Color(spec.accent2); accent3 = Color(spec.accent3)
        line = Color(spec.line)
        blobs = spec.blobs.map(Color.init)
        blobOpacity = spec.blobOpacity
        radius = spec.radius
    }

    static func make(_ id: ThemeID) -> Theme { Theme(ThemeSpec.spec(id)) }
    static let grove = Theme.make(.grove)
    static let all = ThemeID.allCases.map(Theme.make)

    /// Block colours are stored as token names.
    func color(named name: String) -> Color {
        switch name {
        case "accent": accent
        case "accent3": accent3
        case "muted": muted
        default: accent2
        }
    }

    static let blockColorNames = ["accent", "accent2", "accent3", "muted"]

    // MARK: Fonts (all ship with macOS)

    /// Titles and headings.
    func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch kind {
        case .grove: .system(size: size, weight: weight, design: .serif)
        case .minimal: .system(size: size, weight: weight, design: .default)
        case .futuristic: Font.system(size: size, weight: weight, design: .default).width(.expanded)
        case .vintage: Font.custom("Baskerville", size: size).italic().weight(weight)
        }
    }

    /// Text in lists, panels and notes.
    func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch kind {
        case .grove: .system(size: size, weight: weight, design: .rounded)
        case .minimal, .futuristic: .system(size: size, weight: weight, design: .default)
        case .vintage: Font.custom("American Typewriter", size: size).weight(weight)
        }
    }

    /// Times, counts and other numbers.
    func number(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch kind {
        case .grove: .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        case .minimal: .system(size: size, weight: weight, design: .default).monospacedDigit()
        case .futuristic: .system(size: size, weight: weight, design: .monospaced)
        case .vintage: Font.custom("American Typewriter", size: size).weight(weight).monospacedDigit()
        }
    }

    /// Letter spacing of headings.
    var headingTracking: CGFloat { kind == .futuristic ? 1.5 : (kind == .minimal ? -0.2 : 0) }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.grove }
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Text {
    /// A heading in the font, case and spacing of the theme. Futuristic glows.
    func themedHeading(_ theme: Theme, _ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        self.font(theme.heading(size, weight: weight))
            .tracking(theme.headingTracking)
            .textCase(theme.upperHeadings ? .uppercase : nil)
            .shadow(color: theme.glow ? theme.accent.opacity(0.5) : .clear, radius: theme.glow ? 8 : 0)
    }
}

/// A panel: the theme's surface, border and shadow. Futuristic panels are glass.
private struct PanelStyle: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat?
    var border: Color?
    var borderWidth: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radius, style: .continuous)
        let stroke = border ?? theme.line
        let width = borderWidth ?? (theme.hairlines ? 0.5 : 1)
        if theme.glass {
            content
                .glassEffect(.regular.tint(theme.surface), in: shape)
                .overlay(shape.strokeBorder(stroke, lineWidth: width))
        } else {
            content
                .background(shape.fill(theme.surface).shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y))
                .overlay(shape.strokeBorder(stroke, lineWidth: width))
        }
    }

    private var shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        switch theme.kind {
        case .grove: (Color(hex: 0x3C4828, opacity: 0.10), 15, 0, 10)
        case .minimal, .futuristic: (.clear, 0, 0, 0)
        case .vintage: (Color(hex: 0x3A2A1B, opacity: 0.18), 0, 2, 3)
        }
    }
}

extension View {
    func panel(radius: CGFloat? = nil, border: Color? = nil, borderWidth: CGFloat? = nil) -> some View {
        modifier(PanelStyle(radius: radius, border: border, borderWidth: borderWidth))
    }
}
