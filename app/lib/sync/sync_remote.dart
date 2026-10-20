import 'row_change.dart';

/// The remote cannot be reached now. The sync stops; the next one tries again.
class RemoteUnavailable implements Exception {
  const RemoteUnavailable([this.message = 'The remote is not available.']);

  final String message;

  @override
  String toString() => 'RemoteUnavailable: $message';
}

/// The place where the devices of one user put their rows. It holds one
/// entry for each row (table and key): the newest change it was given.
abstract interface class SyncRemote {
  /// Gives [changes] to the remote. The remote keeps a change only when it
  /// has no entry for that row, or when the stamp of the change is higher
  /// than the stamp it holds. Each change it keeps gets the next `seq`.
  Future<void> push(List<RowChange> changes);

  /// The entries with a `seq` higher than [after], lowest first, at most
  /// [limit] of them.
  Future<List<RowChange>> pull({required int after, required int limit});
}
