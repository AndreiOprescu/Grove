import SwiftUI
import GroveCore

struct DataFolderError: LocalizedError {
    var errorDescription: String? { "Grove cannot find its data folder." }
}

/// Export, import, the data folder and the note templates (PLAN §4.4, §5.8).
extension AppStore {
    // MARK: Export and import

    func exportData() throws -> Data { try DataExport.export(from: repos.db) }

    /// Replaces all data with the file. A bad file changes nothing, and the error says why.
    func importData(_ data: Data) throws {
        try DataExport.importData(data, into: repos)
        resetAfterReplace()
        showToast("Data imported.")
    }

    /// Saves the data as it is now (`before-import.sqlite` in the data folder). The window does this before an import.
    @discardableResult
    func saveSafetyCopy() throws -> URL {
        guard let dir = dataFolder else { throw DataFolderError() }
        return try Backup.safetyCopy(db: repos.db, directory: dir)
    }

    // MARK: The data folder

    /// ~/Library/Application Support/Grove/
    var dataFolder: URL? { try? Database.supportDirectory() }

    /// The daily copies, newest first.
    func backupFiles() -> [BackupFile] {
        guard let dir = dataFolder?.appendingPathComponent("Backups") else { return [] }
        return Backup.list(directory: dir).map { url in
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return BackupFile(url: url, day: SettingsRules.backupDay(fileName: url.lastPathComponent), bytes: bytes)
        }
    }

    // MARK: Note templates

    private func templateKey(_ kind: NoteKind) -> String { kind == .weekly ? "notes.weeklyTemplate" : "notes.dailyTemplate" }

    /// The text a new daily or weekly note starts with. The settings table holds the person's own text.
    /// It travels in the export file. An empty text is allowed.
    func template(_ kind: NoteKind) -> String {
        ((try? repos.settings.get(templateKey(kind))) ?? nil) ?? NotesRules.template(kind)
    }

    func setTemplate(_ kind: NoteKind, _ text: String) {
        try? repos.settings.set(templateKey(kind), text)
    }

    func resetTemplate(_ kind: NoteKind) {
        try? repos.settings.remove(templateKey(kind))
    }
}
