import Foundation
import GroveCore

/// The small rules behind the Settings window (PLAN §5.8). Plain functions, so tests can check them.
enum SettingsRules {
    static let snapSteps = [5, 10, 15, 30]
    static let eventLengths = [15, 30, 45, 60, 90, 120]
    static let defaultEventLength = 60
    /// How strong the moving circles look, 0% to 150%. 100% is the theme as designed.
    static let intensityRange = 0.0...1.5

    /// Keeps the working day at least one hour long and inside 00:00 to 24:00.
    /// The value that did not just change gives way: that is the one the person did not touch.
    static func workHours(start: Int, end: Int, startChanged: Bool) -> (start: Int, end: Int) {
        var s = min(max(start, 0), 23 * 60), e = min(max(end, 60), 24 * 60)
        if e - s < 60 {
            if startChanged { e = min(24 * 60, s + 60); s = e - 60 }
            else { s = max(0, e - 60); e = s + 60 }
        }
        return (s, e)
    }

    /// 540 → "09:00"
    static func hourText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// 0 → "When it starts", 5 → "5 minutes before"
    static func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 0: "When it starts"
        case 1: "1 minute before"
        default: "\(minutes) minutes before"
        }
    }

    /// The quiet note under the switch in the Notifications tab.
    static func notifyStatusText(_ status: NotifyAuthorization) -> String {
        switch status {
        case .allowed: "Notifications are allowed for Grove."
        case .notAsked: "Grove has not asked for permission yet."
        case .denied: "Notifications are off for Grove. Turn them on in System Settings to get reminders."
        }
    }

    /// The day in a backup file name: "grove-2026-10-04.sqlite" → 2026-10-04.
    static func backupDay(fileName: String) -> DayKey? {
        guard fileName.hasPrefix("grove-"), fileName.hasSuffix(".sqlite") else { return nil }
        return DayKey.parse(String(fileName.dropFirst("grove-".count).dropLast(".sqlite".count)))
    }
}

/// One copy of the database in the Backups folder.
struct BackupFile: Identifiable, Equatable {
    var url: URL
    var day: DayKey?
    var bytes: Int
    var id: String { url.lastPathComponent }

    var title: String { day.map(NotesRules.dailyTitle) ?? url.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}
