part of 'app_store.dart';

/// The store has no folder on disk (it works in memory).
class DataFolderError implements Exception {
  const DataFolderError();

  @override
  String toString() => 'Grove cannot find its data folder.';
}

/// Export, import, the data folder and the note templates (PLAN §4.4, §5.8).
extension AppStoreData on AppStore {
  // Export and import

  String exportData() => DataExport.export(repos.db);

  /// Replaces all data with the file. A bad file changes nothing, and the
  /// error says why.
  void importData(String data) {
    DataExport.importData(data, repos);
    resetAfterReplace();
    showToast('Data imported.');
  }

  /// Saves the data as it is now (`before-import.sqlite` in the data folder).
  /// The window does this before an import. Returns the path of the copy.
  String saveSafetyCopy() {
    final dir = dataDir;
    if (dir == null) throw const DataFolderError();
    return Backup.safetyCopy(repos.db, directory: dir);
  }

  // The data folder

  /// The daily copies, newest first.
  List<BackupFile> backupFiles() {
    final dir = dataDir;
    if (dir == null) return const [];
    final sep = Platform.pathSeparator;
    return [
      for (final path in Backup.list('$dir${sep}Backups'))
        BackupFile(
          path: path,
          day: SettingsRules.backupDay(fileName: path.split(sep).last),
          bytes: _try(() => File(path).lengthSync()) ?? 0,
        ),
    ];
  }

  // Note templates

  String _templateKey(NoteKind kind) =>
      kind == NoteKind.weekly ? 'notes.weeklyTemplate' : 'notes.dailyTemplate';

  /// The text a new daily or weekly note starts with. The settings table holds
  /// the person's own text. It travels in the export file. An empty text is
  /// allowed.
  String template(NoteKind kind) =>
      _try(() => repos.settings.get(_templateKey(kind))) ??
      NotesRules.template(kind);

  void setTemplate(NoteKind kind, String text) {
    _try(() => repos.settings.set(_templateKey(kind), text));
  }

  void resetTemplate(NoteKind kind) {
    _try(() => repos.settings.remove(_templateKey(kind)));
  }
}
