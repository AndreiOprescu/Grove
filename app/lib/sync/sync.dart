/// Sync between the devices of one user (cross-platform plan F11): an outbox
/// of local changes, push and pull, last write wins per row. Pure Dart. The
/// remote is an interface; the Supabase one comes with the login step.
library;

export 'memory_remote.dart';
export 'outbox.dart';
export 'row_change.dart';
export 'sync_engine.dart';
export 'sync_remote.dart';
