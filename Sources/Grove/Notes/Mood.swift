import SwiftUI

/// How a day felt. It is saved in `notes.mood` of the daily note as 1, 2 or 3.
enum Mood: Int, CaseIterable, Identifiable {
    case rain = 1, cloud = 2, sun = 3

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .rain: "cloud.rain"
        case .cloud: "cloud.sun"
        case .sun: "sun.max"
        }
    }

    var label: String {
        switch self {
        case .rain: "Rough day"
        case .cloud: "Okay day"
        case .sun: "Good day"
        }
    }

    /// The tint of a month cell. Fixed colours, so a mood looks the same in every theme.
    var tint: Color {
        switch self {
        case .rain: Color(red: 0.42, green: 0.55, blue: 0.75)
        case .cloud: Color(red: 0.78, green: 0.68, blue: 0.43)
        case .sun: Color(red: 0.89, green: 0.70, blue: 0.25)
        }
    }
}
