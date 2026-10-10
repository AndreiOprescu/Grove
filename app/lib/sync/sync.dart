/// Sync between the devices of one user (cross-platform plan F11): an outbox
/// of local changes, push and pull, last write wins per row. Pure Dart. The
/// remote and the login are interfaces. The code that talks to Supabase with
/// the package is in `lib/services/supabase_backend.dart`.
library;

export 'auth_gateway.dart';
export 'memory_remote.dart';
export 'outbox.dart';
export 'remote_schema.dart';
export 'row_change.dart';
export 'supabase_api.dart';
export 'supabase_remote.dart';
export 'supabase_sql.dart';
export 'sync_backend.dart';
export 'sync_engine.dart';
export 'sync_remote.dart';
