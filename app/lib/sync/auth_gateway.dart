import 'dart:async';

/// The person who is signed in.
class Account {
  const Account({required this.userId, required this.email});

  final String userId;
  final String email;

  @override
  bool operator ==(Object other) =>
      other is Account && other.userId == userId && other.email == email;

  @override
  int get hashCode => Object.hash(userId, email);

  @override
  String toString() => 'Account($userId, $email)';
}

/// Why a login step did not work.
enum AuthProblem {
  /// No way to the server.
  offline,

  /// The text is not an email address.
  badEmail,

  /// The code is wrong or too old.
  badCode,

  /// Too many emails in a short time. The server says: wait.
  tooMany,

  /// Something else. See the message.
  other,
}

class AuthFailure implements Exception {
  const AuthFailure(this.problem, [this.detail]);

  final AuthProblem problem;

  /// What the server said, when it said something.
  final String? detail;

  /// A line for the screen.
  String get message => switch (problem) {
    AuthProblem.offline => 'No connection. Try again when you are online.',
    AuthProblem.badEmail => 'This is not an email address.',
    AuthProblem.badCode => 'The code is wrong or too old. Get a new email.',
    AuthProblem.tooMany => 'Too many emails. Wait a minute, then try again.',
    AuthProblem.other => detail ?? 'The login did not work.',
  };

  @override
  String toString() => 'AuthFailure(${problem.name}): $message';
}

/// The login with an email (cross-platform plan, point 4: "email magic
/// link"). The real one talks to Supabase (`lib/services/`); the tests use
/// [MemoryAuth].
///
/// One email holds a link and a code. The link signs in when the system
/// opens Grove for it ([changes] then gives the account). The code is typed
/// in Grove ([verifyCode]).
abstract interface class AuthGateway {
  /// The person who is signed in on this device, or null.
  Account? get account;

  /// Gives the new value each time [account] changes.
  Stream<Account?> get changes;

  /// Sends the login email. Throws [AuthFailure].
  Future<void> sendLink(String email);

  /// Signs in with the code of the email. Throws [AuthFailure].
  Future<void> verifyCode({required String email, required String code});

  /// Signs out on this device. The data of the device and of the account
  /// stay as they are.
  Future<void> signOut();
}

/// A login that lives in memory, for tests.
class MemoryAuth implements AuthGateway {
  MemoryAuth({this._account});

  Account? _account;
  final _changes = StreamController<Account?>.broadcast(sync: true);

  /// True: every call fails with "no connection".
  bool offline = false;

  /// The code that is in every email.
  String code = '123456';

  /// The addresses an email went to, oldest first.
  final sent = <String>[];

  /// Set to make the next [sendLink] fail with this.
  AuthFailure? nextFailure;

  /// The id of the account of an address.
  static String userIdOf(String email) => 'user-${email.toLowerCase()}';

  @override
  Account? get account => _account;

  @override
  Stream<Account?> get changes => _changes.stream;

  void _set(Account? account) {
    if (account == _account) return;
    _account = account;
    _changes.add(account);
  }

  void _online() {
    if (offline) throw const AuthFailure(AuthProblem.offline);
  }

  @override
  Future<void> sendLink(String email) async {
    _online();
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    if (!email.contains('@')) throw const AuthFailure(AuthProblem.badEmail);
    sent.add(email);
  }

  @override
  Future<void> verifyCode({required String email, required String code}) async {
    _online();
    if (!sent.contains(email) || code != this.code) {
      throw const AuthFailure(AuthProblem.badCode);
    }
    _set(Account(userId: userIdOf(email), email: email));
  }

  /// The person opened the link of the email, and the system opened Grove.
  void openLink(String email) =>
      _set(Account(userId: userIdOf(email), email: email));

  /// The server ended the session (for example, it is too old).
  void expire() => _set(null);

  @override
  Future<void> signOut() async => _set(null);

  void dispose() => _changes.close();
}
