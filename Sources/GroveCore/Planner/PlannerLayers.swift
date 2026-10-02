import Foundation

/// How one block sits among the blocks it overlaps.
/// Overlapping blocks never share the width. A block that starts later is drawn on top of the one under it,
/// moved a little to the right, so both titles stay readable and the long block keeps almost all of its space.
public struct Layer: Equatable, Sendable {
    /// Paint order. 0 is painted first (lowest). Later start = higher number = on top.
    public var order: Int
    /// 0 when the block lies on nothing.
    public var depth: Int
    /// The block this one sits on.
    public var parent: String?
    /// True when the block starts so close to its parent's start that it would cover the parent's title row.
    /// Such a block is moved further to the right.
    public var tight: Bool
    /// Indent in steps. A far block adds 1, a tight block adds `PlannerMath.tightUnits`. Used to pick the parent.
    public var units: Int

    public init(order: Int, depth: Int, parent: String?, tight: Bool, units: Int) {
        self.order = order; self.depth = depth; self.parent = parent; self.tight = tight; self.units = units
    }
}

extension PlannerMath {
    /// How many "far" steps one "tight" step counts for when a block picks its parent.
    public static let tightUnits = 4

    /// Works out which block sits on which. Spans that only touch (end == start) do not overlap.
    /// - minLength: the shortest length (minutes) a block is drawn at. A 5 minute block drawn 22 points tall
    ///   covers more than 5 minutes, so it counts as `minLength` minutes here.
    /// - tightWithin: a block that starts less than this many minutes after its parent is "tight".
    public static func layoutLayers(_ spans: [Span], minLength: Int = 0, tightWithin: Int = 0) -> [String: Layer] {
        let sorted = spans.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.length != $1.length { return $0.length > $1.length }
            return $0.id < $1.id
        }
        struct Done { var id: String; var start: Int; var visualEnd: Int; var depth: Int; var units: Int; var order: Int }
        var done: [Done] = []
        var result: [String: Layer] = [:]
        for (order, s) in sorted.enumerated() {
            var parent: Done?
            for p in done where p.visualEnd > s.start {
                guard let best = parent else { parent = p; continue }
                if (p.units, p.start, p.order) > (best.units, best.start, best.order) { parent = p }
            }
            var layer = Layer(order: order, depth: 0, parent: nil, tight: false, units: 0)
            if let p = parent {
                let tight = s.start - p.start < tightWithin
                layer.parent = p.id
                layer.tight = tight
                layer.depth = p.depth + 1
                layer.units = p.units + (tight ? tightUnits : 1)
            }
            result[s.id] = layer
            done.append(Done(id: s.id, start: s.start, visualEnd: max(s.end, s.start + minLength),
                             depth: layer.depth, units: layer.units, order: order))
        }
        return result
    }

    /// Left indent in points for every block. A block sits `far` points right of its parent,
    /// or `tight(parentId)` points when it is tight. No indent goes past `maxIndent`.
    /// A tight block moves right to leave the title of its parent visible, so `tight` gets the parent's id.
    public static func indents(_ layers: [String: Layer], far: Double, tight: (String) -> Double, maxIndent: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for (id, layer) in layers.sorted(by: { $0.value.order < $1.value.order }) {
            if let parent = layer.parent, let base = out[parent] {
                out[id] = min(maxIndent, base + (layer.tight ? tight(parent) : far))
            } else {
                out[id] = 0
            }
        }
        return out
    }
}
