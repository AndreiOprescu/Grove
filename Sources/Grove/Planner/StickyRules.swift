import CoreGraphics

/// The small rules behind the sticky notes under the day numbers. Plain functions, so tests can check them.
enum StickyRules {
    /// The strip grows with its notes up to this height, then scrolls.
    static let maxHeight: CGFloat = 150
    /// The height of the strip when it is folded, empty, or not measured yet.
    static let foldedHeight: CGFloat = 26
    /// A note is at least this wide. A narrow day column shows one note per row.
    static let noteMinWidth: CGFloat = 110
    static let spacing: CGFloat = 6

    static func stripHeight(content: CGFloat) -> CGFloat {
        content <= 0 ? foldedHeight : min(content, maxHeight)
    }

    /// How many notes sit side by side in a day column of this width. Always at least one.
    static func columns(cellWidth: CGFloat) -> Int {
        max(1, Int((cellWidth - spacing) / (noteMinWidth + spacing)))
    }

    /// Which of the three accent colours a note uses (0, 1 or 2).
    static func colorIndex(for id: String) -> Int { Int(stableHash(id) % 3) }

    /// A small tilt in degrees, -1.5 to 1.5 in steps of 0.5, so the notes look stuck on by hand.
    static func tilt(for id: String) -> Double { Double(Int(stableHash(id) / 3 % 7) - 3) * 0.5 }

    /// FNV-1a. Swift's `hashValue` changes on every launch, so a note would change colour after a restart.
    static func stableHash(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h ^= UInt32(b); h = h &* 16_777_619 }
        return h
    }
}
