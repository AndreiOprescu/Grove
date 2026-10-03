import SwiftUI

// The small decorations of each theme (PLAN §6.2). The maths is plain so the tests need no view.

/// The now-line pulse: opacity goes from 1 down to 0.45 and back, once every 3.2 s.
enum PulseMath {
    static let period = 3.2
    static let lowest = 0.45

    static func opacity(at seconds: Double) -> Double {
        1 - (1 - lowest) * (1 - cos(2 * .pi * seconds / period)) / 2
    }
}

/// Where the lines of a grid go.
enum GridMath {
    /// Futuristic: a faint grid on the background, one line every 32 pt.
    static let spacing: CGFloat = 32
    /// Vintage: the ruled lines of the note editor, one every 28 pt.
    static let ruledPitch: CGFloat = 28

    /// Positions `0, step, 2*step ...` up to `length`.
    static func lines(length: CGFloat, spacing: CGFloat = GridMath.spacing) -> [CGFloat] {
        guard length >= 0, spacing > 0 else { return [] }
        return Array(stride(from: CGFloat(0), through: length, by: spacing))
    }

    /// Y positions of ruled lines that fall in `minY...maxY`. The first line is one pitch below `top`.
    static func ruledRows(top: CGFloat, pitch: CGFloat = GridMath.ruledPitch, minY: CGFloat, maxY: CGFloat) -> [CGFloat] {
        guard pitch > 0, maxY >= minY else { return [] }
        let first = max(1, Int(((minY - top) / pitch).rounded(.up)))
        let last = Int(((maxY - top) / pitch).rounded(.down))
        guard last >= first else { return [] }
        return (first...last).map { top + CGFloat($0) * pitch }
    }
}

/// Vintage paper: the dots of the noise, the same every time.
enum NoiseMath {
    static func dots(count: Int, size: CGFloat, seed: UInt64) -> [CGPoint] {
        var state = seed
        func next() -> Double {
            // SplitMix64: small, fast, and the same on every run
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        return (0..<max(0, count)).map { _ in CGPoint(x: CGFloat(next()) * size, y: CGFloat(next()) * size) }
    }
}

/// Futuristic: the faint grid behind everything.
struct BackgroundGrid: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            for x in GridMath.lines(length: size.width) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in GridMath.lines(length: size.height) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(theme.line), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Vintage: fine paper noise, drawn once into an image, and a brown vignette that darkens the edges.
struct PaperTexture: View {
    private static let tileSize: CGFloat = 200

    /// Drawn once and kept.
    @MainActor private static let tile: Image? = {
        let content = Canvas { ctx, _ in
            for p in NoiseMath.dots(count: 3000, size: tileSize, seed: 0x6E0_517E) {
                ctx.fill(Path(CGRect(x: p.x, y: p.y, width: 0.5, height: 0.5)), with: .color(.black.opacity(0.04)))
            }
        }
        .frame(width: tileSize, height: tileSize)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return Image(decorative: cg, scale: 2)
    }()

    var body: some View {
        ZStack {
            if let tile = Self.tile { tile.resizable(resizingMode: .tile) }
            GeometryReader { g in
                let m = max(g.size.width, g.size.height)
                RadialGradient(colors: [.clear, Color(.sRGB, red: 90 / 255, green: 60 / 255, blue: 20 / 255, opacity: 0.35)],
                               center: .center, startRadius: m * 0.35, endRadius: m * 0.85)
            }
            .blendMode(.multiply)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The background of a small tag: a soft capsule, or a box with a dashed border where the theme asks for it (Vintage).
    func chipBackground(_ tint: Color, fill: Double = 0.13) -> some View { modifier(ChipBackground(tint: tint, fill: fill)) }
}

private struct ChipBackground: ViewModifier {
    let tint: Color
    let fill: Double
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if theme.dashedChips {
            let shape = RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
            content
                .background(shape.fill(tint.opacity(fill)))
                .overlay(shape.strokeBorder(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        } else {
            content.background(Capsule().fill(tint.opacity(fill)))
        }
    }
}
