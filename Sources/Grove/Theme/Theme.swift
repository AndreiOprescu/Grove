import SwiftUI
import AppKit

extension Color {
    /// Hex like 0xF3EEE3.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that follows light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Colour and shape tokens. M7 adds the other themes; M2 only needs Grove.
struct Theme: Identifiable {
    var id: String
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
    var radius: CGFloat

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

    static let grove = Theme(
        id: "grove", name: "Grove",
        bg: Color(light: 0xF3EEE3, dark: 0x171C16), surface: Color(light: 0xFBF8F1, dark: 0x1F261D),
        surface2: Color(light: 0xECE5D4, dark: 0x2A3327), ink: Color(light: 0x2F3A2C, dark: 0xE6E9DF),
        muted: Color(light: 0x7D8574, dark: 0x8E9886), accent: Color(light: 0x5E7F4F, dark: 0x8DB57A),
        accent2: Color(light: 0xC77B4E, dark: 0xE09A6E), accent3: Color(light: 0xD9B44A, dark: 0xE3C567),
        line: Color(light: 0xDDD3BF, dark: 0x333D30), radius: 16)
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.grove }
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
