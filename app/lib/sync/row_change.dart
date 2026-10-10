/// One row of one synced table, as it travels between a device and the remote.
class RowChange {
  const RowChange({
    required this.table,
    required this.key,
    required this.stamp,
    required this.deleted,
    required this.data,
    this.seq = 0,
  });

  final String table;

  /// The primary key of the row as text. See `SyncSchema.key`.
  final String key;

  /// When the row was changed, on the clock of the device that changed it.
  /// The change with the higher stamp wins.
  final int stamp;

  /// True: the row is gone. [data] is empty then.
  final bool deleted;

  /// Column name to value, in the types SQLite gives (int, double, String,
  /// bytes, null).
  final Map<String, Object?> data;

  /// The number the remote gave this change. It rises with each change the
  /// remote keeps. 0 for a change that was not sent yet.
  final int seq;
}
