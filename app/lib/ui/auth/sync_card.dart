// The login and the state of the sync (cross-platform plan F11). One card
// for the settings screen: the email, the code, then "signed in" with the
// time of the last sync.
import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart' show DialogButton;
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'first_sync_dialog.dart';

/// The words of the sync card. No widget here, so a test can read them.
abstract final class SyncWords {
  /// "today at 14:05", or "on 2026-10-09 at 14:05" for another day.
  static String when(DateTime at, DateTime now) {
    final clock = PlannerMath.clock(at.hour * 60 + at.minute);
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return 'today at $clock';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'on ${at.year}-${two(at.month)}-${two(at.day)} at $clock';
  }

  /// One line that says what the sync does now.
  static String status(AppStore store, {required DateTime now}) {
    final last = store.lastSyncAt;
    final lastLine = last == null
        ? 'No sync yet.'
        : 'Last sync ${when(last, now)}.';
    return switch (store.syncStatus) {
      SyncStatus.off => 'This copy of Grove has no sync.',
      SyncStatus.signedOut => 'Not signed in.',
      SyncStatus.checking => 'Looking at your account…',
      SyncStatus.question => 'Grove waits for your answer.',
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.error => lastLine,
      SyncStatus.upToDate => lastLine,
    };
  }

  /// "3 changes wait for the next sync.", or null when none waits.
  static String? waiting(int count) => switch (count) {
    0 => null,
    1 => '1 change waits for the next sync.',
    _ => '$count changes wait for the next sync.',
  };
}

/// The sync section of the settings screen. It has no frame of its own.
class SyncCard extends StatefulWidget {
  const SyncCard({super.key, required this.store, this.now});

  final AppStore store;

  /// The time of the device. Tests give a fixed one.
  final DateTime Function()? now;

  static const emailKey = ValueKey('sync-email');
  static const codeKey = ValueKey('sync-code');
  static const sendKey = ValueKey('sync-send');
  static const signInKey = ValueKey('sync-sign-in');
  static const otherEmailKey = ValueKey('sync-other-email');
  static const syncNowKey = ValueKey('sync-now');
  static const signOutKey = ValueKey('sync-sign-out');
  static const errorKey = ValueKey('sync-error');

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  AppStore get store => widget.store;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (await store.sendLoginLink(_email.text) && mounted) _code.clear();
  }

  Future<void> _signIn() async {
    if (await store.verifyLoginCode(_code.text) && mounted) {
      _email.clear();
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      return Semantics(
        container: true,
        label: 'Sync',
        child: DefaultTextStyle(
          style: theme.body(13).copyWith(color: theme.ink),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              const ThemedHeading('Sync', 15),
              ...switch (store.syncStatus) {
                SyncStatus.off => _off(theme),
                SyncStatus.signedOut =>
                  store.loginStep == LoginStep.email
                      ? _emailStep(theme)
                      : _codeStep(theme),
                _ => _signedIn(theme),
              },
            ],
          ),
        ),
      );
    },
  );

  Widget _muted(GroveTheme theme, String text) =>
      Text(text, style: theme.body(13).copyWith(color: theme.muted));

  Widget _error(GroveTheme theme, String text) => Text(
    text,
    key: SyncCard.errorKey,
    style: theme.body(12).copyWith(color: theme.accent2),
  );

  List<Widget> _off(GroveTheme theme) => [
    _muted(
      theme,
      'This copy of Grove has no sync. Your data stays on this device.',
    ),
  ];

  List<Widget> _emailStep(GroveTheme theme) {
    final error = store.loginError;
    return [
      _muted(
        theme,
        'Sign in with your email to have the same data on all your '
        'devices. Grove sends you an email with a code. There is no '
        'password.',
      ),
      GroveField(
        key: SyncCard.emailKey,
        controller: _email,
        placeholder: 'Email address',
        boxed: true,
        keyboard: TextInputType.emailAddress,
        plainTyping: true,
        onSubmitted: (_) => _send(),
      ),
      if (error != null) _error(theme, error),
      DialogButton(
        key: SyncCard.sendKey,
        label: store.loginBusy ? 'Sending…' : 'Send the email',
        primary: true,
        onTap: _send,
      ),
    ];
  }

  List<Widget> _codeStep(GroveTheme theme) {
    final error = store.loginError;
    return [
      _muted(
        theme,
        'The email is on its way to ${store.loginEmail}. Type the code of '
        'the email here.',
      ),
      GroveField(
        key: SyncCard.codeKey,
        controller: _code,
        placeholder: 'Code',
        boxed: true,
        autofocus: true,
        keyboard: TextInputType.number,
        plainTyping: true,
        maxLength: 12,
        onSubmitted: (_) => _signIn(),
      ),
      if (error != null) _error(theme, error),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DialogButton(
            key: SyncCard.signInKey,
            label: store.loginBusy ? 'Checking…' : 'Sign in',
            primary: true,
            onTap: _signIn,
          ),
          DialogButton(
            key: SyncCard.otherEmailKey,
            label: 'Use another address',
            onTap: store.changeLoginEmail,
          ),
        ],
      ),
    ];
  }

  List<Widget> _signedIn(GroveTheme theme) {
    final now = (widget.now ?? DateTime.now)();
    final error = store.syncError;
    final waiting = SyncWords.waiting(store.syncWaiting);
    final skipped = store.syncSkipped.length;
    return [
      Text('Signed in as ${store.syncAccount?.email ?? ''}'),
      if (store.firstSyncQuestion) ...[
        _muted(
          theme,
          'This device has data, and your account has data too. What '
          'should Grove do? You choose one time.',
        ),
        FirstSyncChoices(store: store),
      ] else ...[
        _muted(theme, SyncWords.status(store, now: now)),
        if (waiting != null && !store.isSyncing) _muted(theme, waiting),
      ],
      if (error != null) _error(theme, error),
      if (skipped > 0)
        _error(
          theme,
          skipped == 1
              ? '1 row of the account is of a newer Grove and is not shown.'
              : '$skipped rows of the account are of a newer Grove and are '
                    'not shown.',
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!store.firstSyncQuestion)
            DialogButton(
              key: SyncCard.syncNowKey,
              label: 'Sync now',
              onTap: store.syncNow,
            ),
          DialogButton(
            key: SyncCard.signOutKey,
            label: 'Sign out',
            onTap: store.signOut,
          ),
        ],
      ),
    ];
  }
}
