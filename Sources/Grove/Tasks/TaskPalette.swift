import SwiftUI
import GroveCore

/// The eight colours a task can have. The same in every theme.
enum TaskPalette {
    static func color(named name: String) -> Color? {
        switch name {
        case "red": Color(red: 0.90, green: 0.30, blue: 0.30)
        case "orange": Color(red: 0.96, green: 0.58, blue: 0.20)
        case "yellow": Color(red: 0.93, green: 0.76, blue: 0.20)
        case "green": Color(red: 0.34, green: 0.70, blue: 0.40)
        case "teal": Color(red: 0.18, green: 0.66, blue: 0.66)
        case "blue": Color(red: 0.30, green: 0.54, blue: 0.90)
        case "purple": Color(red: 0.62, green: 0.44, blue: 0.85)
        case "pink": Color(red: 0.92, green: 0.44, blue: 0.70)
        default: nil
        }
    }
}
