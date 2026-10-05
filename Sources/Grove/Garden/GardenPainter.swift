import SwiftUI
import GroveCore

/// Draws the garden plant for one growth number (`Garden.growth`, 0 to 11).
/// Nothing in the picture jumps: the stem, the forks, the leaves, the trunk, the canopy and the flowers
/// each grow by a small step with every finished task.
struct GardenPainter {
    var growth: Double
    var leaf: Color
    var bark: Color
    var petal: Color
    var heart: Color
    var soil: Color

    /// Branch levels after the trunk. Each level forks in two at the tip of the one before.
    static let levels = 5

    // MARK: Small maths

    private static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    private static func smooth(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }

    /// A steady "random" number from 0 to 1. The same input always gives the same output, so the tree never flickers.
    static func noise(_ a: Int, _ b: Int = 0) -> Double {
        let x = sin(Double(a) * 12.9898 + Double(b) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    /// How grown level `k` is, from 0 to 1. The trunk is level 0.
    func levelGrowth(_ k: Int) -> Double {
        if k == 0 { return Self.smooth(growth / 3.0) }
        return Self.smooth((growth - (1.5 + 1.8 * Double(k - 1))) / 1.8)
    }

    private var t: Double { growth / Garden.maxGrowth }

    // MARK: Paint

    func paint(_ ctx: GraphicsContext, size: CGSize) {
        // The tree is as wide as it is tall, so it is sized by the smaller side and always fits its box.
        let h = min(size.height * 0.84, size.width / 1.275), w = h * 0.85
        let base = CGPoint(x: size.width / 2, y: size.height * 0.88)
        paintGround(ctx, base: base, w: w, h: h)
        if growth < 0.35 { paintSeed(ctx, base: base, w: w) }
        let trunk = h * (0.20 + 0.08 * t)
        let width = max(1.6, w * (0.006 + 0.034 * t))
        paintBranch(ctx, from: base, angle: 0, level: 0, index: 0, length: trunk, width: width, w: w)
        paintGrassFront(ctx, base: base, w: w, h: h)
    }

    private func paintSeed(_ ctx: GraphicsContext, base: CGPoint, w: CGFloat) {
        let r = w * 0.022
        let fade = 1 - Self.clamp(growth / 0.35)
        let seed = Path(ellipseIn: CGRect(x: base.x - r, y: base.y - r * 1.3, width: r * 2, height: r * 1.5))
        ctx.fill(seed, with: .color(bark.opacity(fade)))
    }

    private func paintGround(_ ctx: GraphicsContext, base: CGPoint, w: CGFloat, h: CGFloat) {
        let half = w * (0.17 + 0.17 * t)
        let mound = Path(ellipseIn: CGRect(x: base.x - half, y: base.y - h * 0.018, width: half * 2, height: h * 0.07))
        ctx.fill(mound, with: .color(soil))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - half, y: base.y - h * 0.018, width: half * 2, height: h * 0.034)),
                 with: .color(leaf.opacity(0.55)))
    }

    /// Grass blades and small flowers on the ground, in front of the trunk. More of them as the plant grows.
    private func paintGrassFront(_ ctx: GraphicsContext, base: CGPoint, w: CGFloat, h: CGFloat) {
        let half = w * (0.17 + 0.17 * t)
        let blades = 4 + Int(14 * t)
        for i in 0..<blades {
            let x = base.x + (Self.noise(i, 3) * 2 - 1) * half * 0.92
            let y = base.y + h * 0.006 + Self.noise(i, 4) * h * 0.016
            let tall = h * (0.016 + 0.020 * Self.noise(i, 5)) * (0.5 + 0.5 * Self.smooth(growth / 2))
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: y))
            blade.addQuadCurve(to: CGPoint(x: x + (Self.noise(i, 6) - 0.5) * tall, y: y - tall),
                               control: CGPoint(x: x, y: y - tall * 0.6))
            ctx.stroke(blade, with: .color(leaf), style: StrokeStyle(lineWidth: max(1, w * 0.004), lineCap: .round))
        }
        let flowers = Int((Self.smooth((growth - 6) / 5) * 7).rounded(.down))
        for i in 0..<flowers {
            let x = base.x + (Self.noise(i, 9) * 2 - 1) * half * 0.85
            let y = base.y + h * 0.012 + Self.noise(i, 10) * h * 0.012
            paintFlower(ctx, at: CGPoint(x: x, y: y), radius: w * 0.010, tone: i)
        }
    }

    // MARK: Branches

    private func mixed(_ k: Int) -> Color {
        let wood = Self.smooth((growth - 3.5) / 4) * max(0, 1 - 0.28 * Double(k))
        return leaf.mix(with: bark, by: wood)
    }

    /// One branch. Its two children grow from its tip.
    private func paintBranch(_ ctx: GraphicsContext, from p: CGPoint, angle: Double, level k: Int, index: Int,
                             length: Double, width: Double, w: CGFloat) {
        let grown = levelGrowth(k)
        guard grown > 0.002 else { return }
        let len = length * grown * (0.9 + 0.2 * Self.noise(k, index))
        let tip = CGPoint(x: p.x + sin(angle) * len, y: p.y - cos(angle) * len)
        let bend = (Self.noise(index, k + 20) - 0.5) * len * 0.22
        let control = CGPoint(x: (p.x + tip.x) / 2 + cos(angle) * bend, y: (p.y + tip.y) / 2 + sin(angle) * bend)
        func point(_ s: Double) -> CGPoint {
            let u = 1 - s
            return CGPoint(x: u * u * p.x + 2 * u * s * control.x + s * s * tip.x,
                           y: u * u * p.y + 2 * u * s * control.y + s * s * tip.y)
        }
        var line = Path()
        line.move(to: p)
        line.addQuadCurve(to: tip, control: control)
        ctx.stroke(line, with: .color(mixed(k)), style: StrokeStyle(lineWidth: max(1.1, width), lineCap: .round))

        // Leaves along the branch, one side then the other. Deeper levels carry more.
        let leafGrowth = Self.clamp((grown - 0.25) / 0.6)
        if leafGrowth > 0 {
            let size = w * (0.078 - 0.038 * t) * leafGrowth
            let stops: [Double] = k >= 2 ? [0.45, 0.72, 1.0] : [0.4, 0.65, 0.9]
            for (j, s) in stops.enumerated() {
                let side: Double = (j + index) % 2 == 0 ? 1 : -1
                paintLeaf(ctx, at: point(s), angle: angle + side * (0.85 + 0.25 * Self.noise(j, index + k)),
                          length: size * (s >= 1.0 ? 1.15 : 0.9))
            }
        }

        if k < Self.levels {
            // The canopy: a tuft of leaves at the tips, once the tree is tall enough.
            let canopy = Self.smooth((growth - 6.5) / 4)
            if k >= 3, canopy > 0 {
                let size = w * 0.045 * canopy * grown
                for j in 0..<6 {
                    let a = Double(j) * .pi / 3 + Self.noise(index, k + j)
                    paintLeaf(ctx, at: tip, angle: a, length: size * (0.9 + 0.4 * Self.noise(j, index)))
                }
            }
            let spread = 0.36 + 0.12 * Self.noise(index, k + 40)
            let next = length * 0.76
            let thin = width * 0.66
            paintBranch(ctx, from: tip, angle: angle - spread, level: k + 1, index: index * 2, length: next, width: thin, w: w)
            paintBranch(ctx, from: tip, angle: angle + spread * (0.8 + 0.4 * Self.noise(index, k + 50)),
                        level: k + 1, index: index * 2 + 1, length: next, width: thin, w: w)
        } else {
            // The last level: flowers at some of the tips.
            let bloom = Self.smooth((growth - 6) / 3)
            if bloom > 0 && index % 2 == 0 {
                paintFlower(ctx, at: tip, radius: w * 0.016 * bloom * grown, tone: index)
            }
        }
    }

    private func paintLeaf(_ ctx: GraphicsContext, at p: CGPoint, angle: Double, length: Double) {
        guard length > 0.4 else { return }
        let tip = CGPoint(x: p.x + sin(angle) * length, y: p.y - cos(angle) * length)
        let mid = CGPoint(x: (p.x + tip.x) / 2, y: (p.y + tip.y) / 2)
        let nx = cos(angle) * length * 0.38, ny = sin(angle) * length * 0.38
        var shape = Path()
        shape.move(to: p)
        shape.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        shape.addQuadCurve(to: p, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        ctx.fill(shape, with: .color(leaf.opacity(0.88)))
    }

    private func paintFlower(_ ctx: GraphicsContext, at c: CGPoint, radius r: Double, tone: Int) {
        guard r > 0.4 else { return }
        let rim = tone % 3 == 1 ? heart : petal
        for k in 0..<5 {
            let a = Double(k) * 2 * .pi / 5
            let o = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            ctx.fill(Path(ellipseIn: CGRect(x: o.x - r * 0.7, y: o.y - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(rim))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1)),
                 with: .color(rim == petal ? heart : petal))
    }
}

/// The picture as a view. `growth` can be between two numbers, so a spring can move it smoothly.
struct GardenDrawing: View, Animatable {
    var growth: Double
    @Environment(\.theme) private var theme

    var animatableData: Double {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        // Vintage swaps the colours, like the small plant: green leaves from accent2, a red flower
        let vintage = theme.kind == .vintage
        let painter = GardenPainter(
            growth: growth,
            leaf: vintage ? theme.accent2 : theme.accent,
            bark: Color(red: 0.43, green: 0.30, blue: 0.20),
            petal: vintage ? theme.accent : theme.accent2,
            heart: theme.accent3,
            soil: Color(red: 0.36, green: 0.25, blue: 0.17))
        Canvas { ctx, size in painter.paint(ctx, size: size) }
    }
}
