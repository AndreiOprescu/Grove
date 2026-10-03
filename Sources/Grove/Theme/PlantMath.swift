import Foundation

/// How much of a day is done. The plant and the "% grown" text read this.
struct PlantProgress: Equatable {
    var done: Int
    var total: Int

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }

    /// The line under the plant.
    var growthText: String { total == 0 ? "Nothing planned today" : "\(percent)% of today grown" }
}

/// The numbers behind the growing plant (PLAN §6.3). Plain maths, so the tests need no view.
enum PlantMath {
    static let maxLeaves = 6
    /// The plant sways 3 degrees to each side, once every 5 seconds.
    static let swayAmplitude = 3.0
    static let swayPeriod = 5.0

    /// 0 for no progress. At least 1 for any progress. 6 when the day is done.
    static func leaves(done: Int, total: Int) -> Int {
        guard total > 0, done > 0 else { return 0 }
        let n = Int((Double(min(done, total)) / Double(total) * Double(maxLeaves)).rounded())
        return max(1, min(maxLeaves, n))
    }

    /// How tall the stem is, from 0.25 (a seedling) to 1 (full height).
    static func stemGrowth(leaves: Int) -> Double { stemGrowth(amount: Double(leaves)) }

    /// The same, for a leaf count that is in between two numbers while the spring moves.
    static func stemGrowth(amount: Double) -> Double {
        0.25 + 0.75 * max(0, min(Double(maxLeaves), amount)) / Double(maxLeaves)
    }

    static func hasFlower(done: Int, total: Int) -> Bool { total > 0 && done >= total }

    static func swayDegrees(at seconds: Double) -> Double {
        swayAmplitude * sin(2 * .pi * seconds / swayPeriod)
    }
}

/// The little show when a task is checked off (PLAN §6.2, §6.3). One style per theme.
enum BurstMath {
    enum Style: Equatable { case leaves, fade, ringAndSparks, stamp }
    struct Particle: Equatable { var angle: Double; var distance: Double }

    static let duration = 0.5
    static let reach = 18.0

    static func style(for theme: ThemeID) -> Style {
        switch theme {
        case .grove: .leaves
        case .minimal: .fade
        case .futuristic: .ringAndSparks
        case .vintage: .stamp
        }
    }

    /// The flying parts. Angles are in degrees. A fade and a stamp have none.
    static func particles(for style: Style) -> [Particle] {
        switch style {
        case .leaves, .ringAndSparks:
            (0..<6).map { Particle(angle: Double($0) * 60, distance: reach) }
        case .fade, .stamp:
            []
        }
    }

    /// How far a part has flown. It starts fast and slows down.
    static func distance(_ full: Double, progress: Double) -> Double {
        let p = max(0, min(1, progress))
        return full * (1 - (1 - p) * (1 - p))
    }

    static func opacity(progress: Double) -> Double { 1 - max(0, min(1, progress)) }
}

enum Greeting {
    static func text(hour: Int) -> String {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        text(hour: calendar.component(.hour, from: date))
    }
}
