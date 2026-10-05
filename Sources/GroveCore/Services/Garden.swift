import Foundation

/// One step on the way from a seed to an old tree.
public struct GardenStage: Equatable, Sendable {
    public let index: Int
    public let name: String
    /// The number of finished tasks at which the plant reaches this stage.
    public let from: Int
}

/// How the garden plant grows with the tasks you finish.
/// `growth` is a smooth number, so every finished task changes the picture a little.
public enum Garden {
    public static let stages: [GardenStage] = [
        ("Seed", 0), ("Sprout", 1), ("Seedling", 3), ("Young plant", 6), ("Leafy plant", 10), ("Bushy plant", 16),
        ("Budding plant", 24), ("Blooming plant", 34), ("Sapling", 48), ("Young tree", 66), ("Full tree", 90), ("Ancient tree", 120),
    ].enumerated().map { GardenStage(index: $0.offset, name: $0.element.0, from: $0.element.1) }

    /// The growth of the last stage.
    public static var maxGrowth: Double { Double(stages.count - 1) }

    public static func stage(done: Int) -> GardenStage {
        stages.last { $0.from <= done } ?? stages[0]
    }

    public static func next(after done: Int) -> GardenStage? {
        let i = stage(done: done).index + 1
        return i < stages.count ? stages[i] : nil
    }

    /// Finished tasks still needed for the next stage. Nil at the top.
    public static func tasksToNext(done: Int) -> Int? {
        next(after: done).map { $0.from - max(0, done) }
    }

    /// How far through the current stage, from 0 up to just under 1. 1 at the top stage.
    public static func progress(done: Int) -> Double {
        let current = stage(done: done)
        guard let next = next(after: done) else { return 1 }
        return Double(max(0, done) - current.from) / Double(next.from - current.from)
    }

    /// 0 for no tasks. The stage number at the start of a stage. In between for the tasks in between.
    public static func growth(done: Int) -> Double {
        let current = stage(done: done)
        guard next(after: done) != nil else { return Double(current.index) }
        return Double(current.index) + progress(done: done)
    }
}
