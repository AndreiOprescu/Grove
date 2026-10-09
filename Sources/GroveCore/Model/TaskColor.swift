import Foundation

/// The colour a task can have: one of eight names, or "" for none.
/// The app turns each name into a real colour. Names are stored, so a theme change never breaks them.
public enum TaskColor {
    public static let names = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"]

    public static func isValid(_ name: String) -> Bool { name.isEmpty || names.contains(name) }
}
