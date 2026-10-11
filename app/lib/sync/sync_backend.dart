import '../data/repos.dart';
import 'auth_gateway.dart';
import 'sync_remote.dart';

/// Where the Supabase project is. The values come from a file that git does
/// not keep (`app/config/supabase.json`, see `app/config/supabase.example.json`),
/// given to the build with `--dart-define-from-file`.
class SyncConfig {
  const SyncConfig({required this.url, required this.anonKey});

  /// What the build was given. Both are empty when the file is not there.
  static const fromEnvironment = SyncConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final String url;
  final String anonKey;

  /// True when there is a web address with `https` (or `http` for a server
  /// on this computer) and a key. False: Grove runs with no sync.
  bool get isSet {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty || anonKey.trim().isEmpty) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }
}

/// What the store needs for the sync: the login and the remote.
class SyncBackend {
  const SyncBackend({required this.auth, required this.remote});

  final AuthGateway auth;

  /// Makes the remote for the database of this device.
  final SyncRemote Function(Repos repos) remote;
}
