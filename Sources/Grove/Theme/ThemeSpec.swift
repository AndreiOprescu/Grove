import SwiftUI

enum ThemeID: String, CaseIterable, Identifiable {
    case grove, minimal, futuristic, vintage
    var id: String { rawValue }
    static let `default`: ThemeID = .grove

    /// The theme after this one. The last wraps around to the first.
    var next: ThemeID {
        let all = ThemeID.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// One colour in its light and its dark form, each with an opacity.
struct Tone: Equatable {
    var light: UInt32
    var dark: UInt32
    var lightAlpha = 1.0
    var darkAlpha = 1.0

    init(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.light = light; self.dark = dark; self.lightAlpha = lightAlpha; self.darkAlpha = darkAlpha
    }

    /// One colour for both modes (the themes that do not change with light and dark).
    static func fixed(_ hex: UInt32, alpha: Double = 1) -> Tone {
        Tone(hex, hex, lightAlpha: alpha, darkAlpha: alpha)
    }

    func rgb(dark isDark: Bool) -> UInt32 { isDark ? dark : light }
    func alpha(dark isDark: Bool) -> Double { isDark ? darkAlpha : lightAlpha }
}

/// Which look the window is forced into. Grove and Minimal follow the Mac; the other two have one look.
enum SchemeLock: Equatable { case system, light, dark }

/// The numbers of one theme (PLAN §6.1). Plain data, so the tests can check it without any view.
struct ThemeSpec {
    var id: ThemeID
    var name: String
    var scheme: SchemeLock
    var bg, surface, surface2, ink, muted, accent, accent2, accent3, line: Tone
    var blobs: [Tone]
    var radius: CGFloat
    /// How strong the three ambient circles are.
    var blobOpacity: Double

    var colorScheme: ColorScheme? {
        switch scheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var allTones: [Tone] { [bg, surface, surface2, ink, muted, accent, accent2, accent3, line] + blobs }

    static func spec(_ id: ThemeID) -> ThemeSpec { all.first { $0.id == id }! }

    static let all: [ThemeSpec] = [grove, minimal, futuristic, vintage]

    static let grove = ThemeSpec(
        id: .grove, name: "Grove", scheme: .system,
        bg: Tone(0xF3EEE3, 0x171C16), surface: Tone(0xFBF8F1, 0x1F261D), surface2: Tone(0xECE5D4, 0x2A3327),
        ink: Tone(0x2F3A2C, 0xE6E9DF), muted: Tone(0x7D8574, 0x8E9886), accent: Tone(0x5E7F4F, 0x8DB57A),
        accent2: Tone(0xC77B4E, 0xE09A6E), accent3: Tone(0xD9B44A, 0xE3C567), line: Tone(0xDDD3BF, 0x333D30),
        blobs: [Tone(0xA9C79A, 0x3F5E35), Tone(0xF2C6A0, 0x6E4A33), Tone(0xE8DC9A, 0x5E5630)],
        radius: 16, blobOpacity: 0.55)

    static let minimal = ThemeSpec(
        id: .minimal, name: "Minimal", scheme: .system,
        bg: Tone(0xF7F7F5, 0x121212), surface: Tone(0xFFFFFF, 0x1B1B1B), surface2: Tone(0xF0F0ED, 0x262626),
        ink: Tone(0x1B1B1A, 0xEDEDEA), muted: Tone(0x8C8C88, 0x8A8A86), accent: Tone(0x1B1B1A, 0xEDEDEA),
        accent2: Tone(0x7C9A7E, 0x93B596), accent3: Tone(0xB9B9B4, 0x6B6B67), line: Tone(0xE6E6E2, 0x2C2C2C),
        blobs: [Tone(0xE9EEE6, 0x1E241F), Tone(0xF1EEE8, 0x242220), Tone(0xEDEDED, 0x202020)],
        radius: 10, blobOpacity: 0.35)

    static let futuristic = ThemeSpec(
        id: .futuristic, name: "Futuristic", scheme: .dark,
        bg: .fixed(0x070B16), surface: .fixed(0x161E3A, alpha: 0.55), surface2: .fixed(0x3C508C, alpha: 0.22),
        ink: .fixed(0xE4F0FF), muted: .fixed(0x7F8DB4), accent: .fixed(0x46F0D2),
        accent2: .fixed(0xA27BFF), accent3: .fixed(0xFF6FB5), line: .fixed(0x78A0FF, alpha: 0.20),
        blobs: [.fixed(0x1FD1B5), .fixed(0x7B4DFF), .fixed(0xFF4FA3)],
        radius: 14, blobOpacity: 0.35)

    static let vintage = ThemeSpec(
        id: .vintage, name: "Vintage", scheme: .light,
        bg: .fixed(0xE6D8BA), surface: .fixed(0xF3E9D2), surface2: .fixed(0xE7D8B6),
        ink: .fixed(0x3A2A1B), muted: .fixed(0x87705A), accent: .fixed(0x8C3B2E),
        accent2: .fixed(0x3F5B4A), accent3: .fixed(0xB8862B), line: .fixed(0xC8B38D),
        blobs: [.fixed(0xF0D9A8), .fixed(0xE2B98A), .fixed(0xF5E6C0)],
        radius: 3, blobOpacity: 0.55)
}

/// Colour arithmetic for the contrast test.
enum ColorMath {
    /// `top` at `alpha` laid over `bottom`, both 0xRRGGBB.
    static func over(_ top: UInt32, alpha: Double, on bottom: UInt32) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let t = Double((top >> shift) & 0xFF), b = Double((bottom >> shift) & 0xFF)
            return UInt32((t * alpha + b * (1 - alpha)).rounded())
        }
        return mix(16) << 16 | mix(8) << 8 | mix(0)
    }

    /// WCAG relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// WCAG contrast ratio, 1 to 21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
