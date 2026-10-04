import SwiftUI

/// The box in front of a task (PLAN §6.2): round in Grove and Minimal, square in Futuristic and Vintage.
/// It only draws. The button around it does the work. When it turns on, it plays the theme's burst.
struct CheckBox: View {
    let isOn: Bool
    var size: CGFloat = 17
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstID = 0
    @State private var bursting = false

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }
    private var shape: AnyShape {
        theme.squareChecks ? AnyShape(RoundedRectangle(cornerRadius: max(2, size * 0.16), style: .continuous)) : AnyShape(Circle())
    }

    var body: some View {
        ZStack {
            shape.stroke(isOn ? theme.accent : theme.muted, lineWidth: 1.5).padding(0.75)
            shape.fill(theme.accent)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(theme.bg)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: size, height: size)
        // The whole square takes the click. An empty box is only a thin ring, and clicks in the middle went to the row.
        .contentShape(Rectangle())
        .shadow(color: theme.glow && isOn ? theme.accent.opacity(0.55) : .clear, radius: 5)
        .animation(motionOn ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: isOn)
        .overlay {
            if bursting {
                CheckBurst(style: BurstMath.style(for: theme.kind), size: size).id(burstID)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: isOn) { was, now in
            guard now, !was, motionOn else { return }
            burstID += 1
            bursting = true
            let id = burstID
            Task {
                try? await Task.sleep(for: .seconds(BurstMath.duration + 0.05))
                if burstID == id { bursting = false }
            }
        }
    }
}

/// The little show when a task is checked off. Leaves in Grove, a fade in Minimal,
/// a ring and sparks in Futuristic, an ink stamp in Vintage (PLAN §6.2).
struct CheckBurst: View {
    let style: BurstMath.Style
    let size: CGFloat
    @Environment(\.theme) private var theme
    @State private var progress = 0.0
    @State private var stampIn = false
    @State private var stampOut = false

    var body: some View {
        ZStack {
            switch style {
            case .leaves:
                ForEach(Array(BurstMath.particles(for: .leaves).enumerated()), id: \.offset) { _, p in
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(theme.accent)
                        .rotationEffect(.degrees(p.angle + 90))
                        .modifier(Fly(particle: p, progress: progress))
                }
            case .fade:
                RoundedRectangle(cornerRadius: size / 2, style: .continuous)
                    .fill(theme.accent.opacity(0.35))
                    .frame(width: size, height: size)
                    .scaleEffect(1 + 0.7 * progress)
                    .opacity(BurstMath.opacity(progress: progress))
            case .ringAndSparks:
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .stroke(theme.accent, lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(0.8 + 1.4 * progress)
                    .opacity(BurstMath.opacity(progress: progress))
                ForEach(Array(BurstMath.particles(for: .ringAndSparks).enumerated()), id: \.offset) { _, p in
                    Rectangle()
                        .fill(theme.accent3)
                        .frame(width: 3, height: 3)
                        .shadow(color: theme.accent3.opacity(0.8), radius: 3)
                        .modifier(Fly(particle: p, progress: progress))
                }
            case .stamp:
                Text("DONE")
                    .font(theme.number(9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .overlay(Rectangle().stroke(theme.accent, lineWidth: 1.2))
                    .fixedSize()
                    .rotationEffect(.degrees(stampIn ? -8 : -40))
                    .scaleEffect(stampIn ? 1 : 1.8)
                    .opacity(stampOut ? 0 : (stampIn ? 1 : 0))
                    .offset(x: size / 2 + 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: BurstMath.duration)) { progress = 1 }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { stampIn = true }
            withAnimation(.easeIn(duration: 0.2).delay(0.3)) { stampOut = true }
        }
    }

    /// Moves a part out along its angle and fades it.
    private struct Fly: ViewModifier {
        let particle: BurstMath.Particle
        let progress: Double

        func body(content: Content) -> some View {
            let d = BurstMath.distance(particle.distance, progress: progress)
            let a = particle.angle * .pi / 180
            content
                .offset(x: cos(a) * d, y: sin(a) * d)
                .opacity(BurstMath.opacity(progress: progress))
        }
    }
}
