import SwiftUI

/// Where one blob is at a time. Plain maths, so a test can check it stays on screen.
enum AmbientMath {
    /// The three periods in seconds (PLAN §6.3).
    static let periods: [Double] = [22, 28, 34]

    /// Centre of blob `index` in 0...1 of the window, at `time` seconds. A slow Lissajous path.
    static func centre(index: Int, time: Double) -> (x: Double, y: Double) {
        let period = periods[index % periods.count]
        let phase = Double(index) * 2.1
        let w = 2 * Double.pi / period
        let x = 0.5 + 0.2 * sin(w * time + phase)
        let y = 0.5 + 0.2 * sin(w * time * 1.15 + phase * 1.7 + 1)
        return (x, y)
    }

    /// How strong the circles are: the theme's strength times the Accent intensity setting, kept between 0 and 1.
    static func strength(base: Double, intensity: Double) -> Double { min(1, max(0, base * intensity)) }

    /// Blob diameter: 46% of the longer side of the window.
    static func diameter(width: Double, height: Double) -> Double { 0.46 * max(width, height) }
}

/// Three big soft circles in the colours of the theme, drifting slowly behind everything (PLAN §6.3).
/// With motion off it draws one still frame. While the window is not the key window it stops.
struct AmbientBackground: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @AppStorage("appearance.intensity") private var intensity = 1.0

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }
    private var runs: Bool { MotionRules.ambientRuns(motionOn: motionOn, windowIsKey: activeState != .inactive) }

    var body: some View {
        // `paused` stops the clock. The blobs then stay where they were.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !runs)) { context in
            Canvas { gc, size in
                let t = motionOn ? context.date.timeIntervalSinceReferenceDate : 0
                let d = AmbientMath.diameter(width: size.width, height: size.height)
                for (i, colour) in theme.blobs.enumerated() {
                    let c = AmbientMath.centre(index: i, time: t)
                    let centre = CGPoint(x: c.x * size.width, y: c.y * size.height)
                    let rect = CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d)
                    // A soft edge from a gradient. It looks like a blur, costs less, and also draws in a snapshot.
                    let strength = AmbientMath.strength(base: theme.blobOpacity, intensity: intensity)
                    let fade = Gradient(stops: [
                        .init(color: colour.opacity(strength), location: 0),
                        .init(color: colour.opacity(strength * 0.55), location: 0.5),
                        .init(color: colour.opacity(0), location: 1),
                    ])
                    gc.fill(Path(ellipseIn: rect), with: .radialGradient(fade, center: centre, startRadius: 0, endRadius: d / 2))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
