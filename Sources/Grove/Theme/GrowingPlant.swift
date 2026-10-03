import SwiftUI

/// A small plant that grows with the day (PLAN §6.3): up to six leaves, a flower when all is done.
/// The stem and leaves grow with a spring. The plant sways 3 degrees over 5 seconds when motion is on.
struct GrowingPlant: View {
    let progress: PlantProgress
    var height: CGFloat = 40
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }
    private var leaves: Int { PlantMath.leaves(done: progress.done, total: progress.total) }
    private var flower: Bool { PlantMath.hasFlower(done: progress.done, total: progress.total) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motionOn)) { context in
            PlantDrawing(amount: Double(leaves), flower: flower)
                .rotationEffect(.degrees(motionOn ? PlantMath.swayDegrees(at: context.date.timeIntervalSinceReferenceDate) : 0),
                                anchor: .bottom)
        }
        .frame(width: height * 0.8, height: height)
        .animation(motionOn ? .spring(response: 0.5, dampingFraction: 0.6) : nil, value: leaves)
        .accessibilityElement()
        .accessibilityLabel("Plant")
        .accessibilityValue(progress.total == 0 ? "Nothing planned today" : "\(progress.percent) percent of today grown")
    }
}

/// The picture. `amount` is the number of leaves as a number that can be in between, so the spring can move it.
private struct PlantDrawing: View, Animatable {
    var amount: Double
    var flower: Bool
    @Environment(\.theme) private var theme

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let potTop = h * 0.84
            let growth = PlantMath.stemGrowth(amount: amount)
            let base = CGPoint(x: w / 2, y: potTop)
            let top = CGPoint(x: w / 2 + w * 0.04, y: potTop - (potTop - h * 0.22) * growth)
            // Vintage swaps the colours: green leaves, an ochre pot, a red flower
            let vintage = theme.kind == .vintage
            let green = vintage ? theme.accent2 : theme.accent
            let potColor = vintage ? theme.accent3 : theme.accent2
            let petal = vintage ? theme.accent : theme.accent2

            // pot
            var pot = Path()
            pot.move(to: CGPoint(x: w * 0.22, y: potTop))
            pot.addLine(to: CGPoint(x: w * 0.78, y: potTop))
            pot.addLine(to: CGPoint(x: w * 0.68, y: h))
            pot.addLine(to: CGPoint(x: w * 0.32, y: h))
            pot.closeSubpath()
            ctx.fill(pot, with: .color(potColor))

            // stem
            let control = CGPoint(x: w * 0.36, y: (base.y + top.y) / 2)
            func point(_ t: Double) -> CGPoint {
                let u = 1 - t
                return CGPoint(x: u * u * base.x + 2 * u * t * control.x + t * t * top.x,
                               y: u * u * base.y + 2 * u * t * control.y + t * t * top.y)
            }
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: top, control: control)
            ctx.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: max(1.5, w * 0.06), lineCap: .round))

            // leaves, bottom to top, one on each side
            for i in 0..<PlantMath.maxLeaves {
                let grown = max(0, min(1, amount - Double(i)))
                guard grown > 0 else { continue }
                let t = 0.3 + 0.12 * Double(i)
                let p = point(min(t, 0.95))
                let side: Double = i % 2 == 0 ? 1 : -1
                let len = w * 0.34 * grown
                let angle = side * (-0.7) - .pi / 2 + (side > 0 ? 0.2 : -0.2)
                var leaf = Path()
                let tip = CGPoint(x: p.x + cos(angle) * len * 1.2, y: p.y + sin(angle) * len * 1.2)
                let mid = CGPoint(x: (p.x + tip.x) / 2, y: (p.y + tip.y) / 2)
                let nx = -sin(angle) * len * 0.45, ny = cos(angle) * len * 0.45
                leaf.move(to: p)
                leaf.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
                leaf.addQuadCurve(to: p, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
                ctx.fill(leaf, with: .color(green.opacity(0.85)))
            }

            // flower
            if flower {
                let r = w * 0.12
                for k in 0..<5 {
                    let a = Double(k) * 2 * .pi / 5
                    let c = CGPoint(x: top.x + cos(a) * r, y: top.y + sin(a) * r)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.7, width: r * 1.4, height: r * 1.4)),
                             with: .color(petal))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: top.x - r * 0.6, y: top.y - r * 0.6, width: r * 1.2, height: r * 1.2)),
                         with: .color(theme.accent3))
            }
        }
    }
}
